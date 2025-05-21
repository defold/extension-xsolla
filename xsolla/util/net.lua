local log = require "xsolla.util.log"
local b64 = require "xsolla.util.b64"
local uri = require "xsolla.util.uri"
local uuid = require "xsolla.util.uuid"

b64.encode = _G.crypt and _G.crypt.encode_base64 or b64.encode
b64.decode = _G.crypt and _G.crypt.decode_base64 or b64.decode

local b64_encode = b64.encode
local b64_decode = b64.decode
local uri_encode_component = uri.encode_component
local uri_decode_component = uri.decode_component
local uri_encode = uri.encode
local uri_decode = uri.decode

uuid.seed()

local M = {}

--- Get the device's mac address.
-- @return The mac address string.
local function get_mac_address()
	local ifaddrs = sys.get_ifaddrs()
	for _,interface in ipairs(ifaddrs) do
		if interface.mac then
			return interface.mac
		end
	end
	return nil
end

--- Returns a UUID from the device's mac address.
-- @return The UUID string.
function M.uuid()
	local mac = get_mac_address()
	if not mac then
		log("Unable to get hardware mac address for UUID")
	end
	return uuid(mac)
end


local make_http_request
make_http_request = function(url, method, callback, headers, post_data, options, retry_intervals, retry_count, cancellation_token)
	if cancellation_token and cancellation_token.cancelled then
		callback(nil)
		return
	end
	http.request(url, method, function(self, id, result)
		if cancellation_token and cancellation_token.cancelled then
			callback(nil)
			return
		end
		log(result.status, result.response)
		local ok, decoded = pcall(json.decode, result.response)
		-- return result if everything is ok
		if ok and result.status >= 200 and result.status <= 299 then
			result.response = decoded
			callback(result.response)
			return
		end

		-- return the error if there are no more retries
		if retry_count > #retry_intervals then
			if not ok then
				result.response = { error = true, message = "Unable to decode response" }
			else
				result.response = { error = true, message = decoded.errorMessage, code = decoded.errorCode }
			end
			callback(result.response)
			return
		end

		-- retry!
		local retry_interval = retry_intervals[retry_count]
		timer.delay(retry_interval, false, function()
			make_http_request(url, method, callback, headers, post_data, options, retry_intervals, retry_count + 1, cancellation_token)
		end)
	end, headers, post_data, options)

end



--- Make a HTTP request.
-- @param config The http config table, see Defold docs.
-- @param url_path The request URL.
-- @param query_params Query params string.
-- @param method The HTTP method string.
-- @param post_data String of post data.
-- @param callback The callback function.
-- @return The mac address string.
function M.http(config, url_path, query_params, method, post_data, retry_policy, cancellation_token, callback)
	local query_string = ""
	if next(query_params) then
		for query_key,query_value in pairs(query_params) do
			if type(query_value) == "table" then
				for _,v in ipairs(query_value) do
					query_string = ("%s%s%s=%s"):format(query_string, (#query_string == 0 and "?" or "&"), query_key, uri_encode_component(tostring(v)))
				end
			else
				query_string = ("%s%s%s=%s"):format(query_string, (#query_string == 0 and "?" or "&"), query_key, uri_encode_component(tostring(query_value)))
			end
		end
	end
	local url = ("%s%s%s"):format(config.http_uri, url_path, query_string)

	local headers = {}
	if post_data then
		headers["Content-Type"] = "application/json"
	end
	if config.bearer_token then
		headers["Authorization"] = ("Bearer %s"):format(config.bearer_token)
	elseif config.username then
		local credentials = b64_encode(config.username .. ":" .. config.password)
		headers["Authorization"] = ("Basic %s"):format(credentials)
	end

	local options = {
		timeout = config.timeout
	}

	log("HTTP", method, url)
	log("DATA", post_data)
	make_http_request(url, method, callback, headers, post_data, options, retry_policy or config.retry_policy, 1, cancellation_token)
end

return M
