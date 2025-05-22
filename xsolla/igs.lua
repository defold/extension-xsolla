local log = require("xsolla.util.log")
local net = require("xsolla.util.net")
local uri = require("xsolla.util.uri")
local async = require("xsolla.util.async")
local retries = require("xsolla.util.retries")
local b64 = require "xsolla.util.b64"

local M = {}

local SERVERS = {
    "https://store.xsolla.com/api",
}

local authorization = {
    bearer = nil,
    basic = nil,
    merchant = nil,
    x_unauthorized_id = nil,
    x_user = nil,
}

local config = {
    http_uri = SERVERS[1],
    bearer_token = nil,
    username = nil,
    password = nil,
    timeout = 3,    -- seconds
    retry_policy = retries.fixed(5, 0.5),
}

-- cancellation tokens associated with a coroutine
local cancellation_tokens = {}

--- cancel a cancellation token
function M.cancel(token)
    assert(token)
    token.cancelled = true
end

--- create a cancellation token
-- use this to cancel an ongoing API call or a sequence of API calls
-- @return token Pass the token to a call to xsolla.sync() or to any of the API calls
function M.cancellation_token()
    local token = {
        cancelled = false
    }
    function token.cancel()
        token.cancelled = true
    end
    return token
end

--- set bearer token for authorization
-- @param bearer_token
function M.set_bearer_token(bearer_token)
    config.bearer_token = bearer_token
    authorization.bearer = ("Bearer %s"):format(bearer_token)
end

--- set username and password for authorization
-- @param username
-- @param password
function M.set_username_password(username, password)
    config.username = username
    config.password = password
    local credentials = b64_encode(config.username .. ":" .. config.password)
    authorization.basic = ("Basic %s"):format(credentials)
end

--- set merchant id and api key for use with 'basicMerchantAuth' authentication
-- @param merchant_id
-- @param api_key
function M.set_merchant_auth(merchant_id, api_key)
    local credentials = b64_encode(merchant_id .. ":" .. api_key)
    authorization.merchant = ("Basic %s"):format(credentials)
end

--- set authorization when using 'AuthForCart' authentication
-- @param authorization_id unique identifier
-- @param user e-mail
function M.set_auth_for_cart(authorization_id, user)
    authorization.x_unauthorized_id = authorization_id
    authorization.x_user = b64_encode(user)
end

-- Private
-- Run code within a coroutine
-- @param fn The code to run
-- @param cancellation_token Optional cancellation token to cancel the running code
-- @return result or false if an error occurred
-- @return error or nil if no error occurred
function M.sync(fn, cancellation_token)
    assert(fn)
    local result
    local ok, err
    local co = coroutine.running()
    if co then
        ok, err = pcall(function()
            cancellation_tokens[co] = cancellation_token
            result = fn()
            cancellation_tokens[co] = nil
        end)
    else
        co = coroutine.create(function()
            cancellation_tokens[co] = cancellation_token
            result = fn()
            cancellation_tokens[co] = nil
        end)
        ok, err = coroutine.resume(co)
    end
    if not ok then
        log(err)
        cancellation_tokens[co] = nil
        result = false
    end
    return result, err
end

-- http request helper used to reduce code duplication in all API functions below
local function http(callback, url_path, query_params, method, headers, post_data, retry_policy, cancellation_token, handler_fn)
    if callback then
        log(url_path, "with callback")
        net.http(config, url_path, query_params, method, headers, post_data, retry_policy, cancellation_token, function(result)
            if not cancellation_token or not cancellation_token.cancelled then
                if result.error then
                    callback(handler_fn(false, result))
                else
                    callback(handler_fn(result))
                end
            end
        end)
    else
        log(url_path, "with coroutine")
        local co = coroutine.running()
        assert(co, "You must be running this from within a coroutine")

        -- get cancellation token associated with this coroutine
        cancellation_token = cancellation_tokens[co]
        if cancellation_token and cancellation_token.cancelled then
            cancellation_tokens[co] = nil
            return
        end

        return async(function(done)
            net.http(config, url_path, query_params, method, headers, post_data, retry_policy, cancellation_token, function(result)
                if cancellation_token and cancellation_token.cancelled then
                    cancellation_tokens[co] = nil
                    return
                end
                if result.error then
                    done(handler_fn(false, result))
                else
                    done(handler_fn(result))
                end
            end)
        end)
    end
end


--- Get list of bundles
-- Gets a list of bundles for building a catalog.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. 
-- Note
-- In general, the use of catalog of items is available without authorization.
-- Only authorized users can get a personalized catalog.
-- @path /v2/project/{project_id}/items/bundle
-- @name get_bundle_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_bundle_list(project_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/bundle"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get specified bundle
-- Gets a specified bundle.
-- 
-- Note
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- @path /v2/project/{project_id}/items/bundle/sku/{sku}
-- @name get_bundle
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param sku (REQUIRED) Bundle SKU.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_bundle(project_id, sku, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(sku)

    local url_path = "/v2/project/{project_id}/items/bundle/sku/{sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{sku}", uri.encode(tostring(sku)))

    local query_params = {}
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get list of bundles by specified group
-- Gets a list of bundles within a group for building a catalog.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. 
-- Note
-- In general, the use of catalog of items is available without authorization.
-- Only authorized users can get a personalized catalog.
-- @path /v2/project/{project_id}/items/bundle/group/{external_id}
-- @name get_bundle_list_in_group
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Group external ID.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_bundle_list_in_group(project_id, external_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/items/bundle/group/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get cart by cart ID
-- Returns user’s cart by cart ID.
-- @path /v2/project/{project_id}/cart/{cart_id}
-- @name get_cart_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param currency The item price currency displayed in the cart. Three-letter currency code per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). Check the documentation for detailed information about [currencies supported by Xsolla](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_cart_by_id(project_id, cart_id, currency, locale, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/project/{project_id}/cart/{cart_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))

    local query_params = {}
    query_params["currency"] = currency
    query_params["locale"] = locale

    local post_data = nil

    local headers = {}
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get current user&#x27;s cart
-- Returns the current user&#x27;s cart.
-- @path /v2/project/{project_id}/cart
-- @name get_user_cart
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param currency The item price currency displayed in the cart. Three-letter currency code per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). Check the documentation for detailed information about [currencies supported by Xsolla](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_user_cart(project_id, currency, locale, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/cart"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["currency"] = currency
    query_params["locale"] = locale

    local post_data = nil

    local headers = {}
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Delete all cart items by cart ID
-- Deletes all cart items.
-- @path /v2/project/{project_id}/cart/{cart_id}/clear
-- @name cart_clear_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.cart_clear_by_id(project_id, cart_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/project/{project_id}/cart/{cart_id}/clear"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))

    local query_params = {}

    local post_data = nil

    local headers = {}
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "PUT", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Delete all cart items from current cart
-- Deletes all cart items.
-- @path /v2/project/{project_id}/cart/clear
-- @name cart_clear
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.cart_clear(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/cart/clear"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    local headers = {}
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "PUT", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Fill cart with items
-- Fills the cart with items. If the cart already has an item with the same SKU, the existing item will be replaced by the passed value.
-- @path /v2/project/{project_id}/cart/fill
-- @name cart_fill
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   items = 
--   {
--     {
--       sku = "com.xsolla.booster_mega_1",
--       quantity = 123,
--     },
--   },
-- }
function M.cart_fill(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/cart/fill"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "PUT", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Fill specific cart with items
-- Fills the specific cart with items. If the cart already has an item with the same SKU, the existing item position will be replaced by the passed value.
-- @path /v2/project/{project_id}/cart/{cart_id}/fill
-- @name cart_fill_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   items = 
--   {
--     {
--       sku = "com.xsolla.booster_mega_1",
--       quantity = 123,
--     },
--   },
-- }
function M.cart_fill_by_id(project_id, cart_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/project/{project_id}/cart/{cart_id}/fill"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "PUT", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update cart item by cart ID
-- Updates an existing cart item or creates the one in the cart.
-- @path /v2/project/{project_id}/cart/{cart_id}/item/{item_sku}
-- @name put_item_by_cart_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   quantity = 123.456,
-- }
function M.put_item_by_cart_id(project_id, cart_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(cart_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/cart/{cart_id}/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "PUT", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Delete cart item by cart ID
-- Removes an item from the cart.
-- @path /v2/project/{project_id}/cart/{cart_id}/item/{item_sku}
-- @name delete_item_by_cart_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.delete_item_by_cart_id(project_id, cart_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(cart_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/cart/{cart_id}/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    local headers = {}
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "DELETE", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update cart item from current cart
-- Updates an existing cart item or creates the one in the cart.
-- @path /v2/project/{project_id}/cart/item/{item_sku}
-- @name put_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   quantity = 123.456,
-- }
function M.put_item(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/cart/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "PUT", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Delete cart item from current cart
-- Removes an item from the cart.
-- @path /v2/project/{project_id}/cart/item/{item_sku}
-- @name delete_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.delete_item(project_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/cart/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    local headers = {}
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "DELETE", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create order with all items from particular cart
-- Used for client-to-server integration. Creates an order with all items from the particular cart and generates a payment token for it. The created order gets the `new` order status.
-- 
-- The client IP is used to determine the user’s country, which is then used to apply the corresponding currency and available payment methods for the order.
-- 
-- To open the payment UI in a new window, use the following link: `https://secure.xsolla.com/paystation4/?token={token}`, where `{token}` is the received token.
-- 
-- For testing purposes, use this URL: `https://sandbox-secure.xsolla.com/paystation4/?token={token}`.
-- 
-- Notice 
--  As this method uses the IP to determine the user’s country and select a currency for the order, it is important to only use this method from the client side and not from the server side. Using this method from the server side may cause incorrect currency determination and affect payment methods in Pay Station. 
-- @path /v2/project/{project_id}/payment/cart/{cart_id}
-- @name create_order_by_cart_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   currency = "Order price currency. Three-letter currency code per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). Check the documentation for detailed information about [currencies supported by Xsolla](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/).",
--   locale = "Response language.",
--   sandbox = true,
--   settings = 
--   {
--     cart_payment_settings_ui = 
--     {
--       theme = "Payment UI theme. Can be `63295a9a2e47fab76f7708e1` for the light theme (default) or `63295aab2e47fab76f7708e3` for the dark theme. You can also [create a custom theme](https://developers.xsolla.com/doc/pay-station/features/ui-theme-customization/#pay_station_ui_theme_customization_in_token) and pass its ID in this parameter.",
--       desktop = 
--       {
--         header = 
--         {
--           is_visible = true,
--           visible_logo = true,
--           visible_name = true,
--           visible_purchase = true,
--           type = "How to show the header. Can be `compact` (hides project name and user ID) or `normal` (default).",
--           close_button = true,
--         },
--       },
--       mode = "Interface mode in payment UI. Can be `user_account` only. The header contains only the account navigation menu, and the user cannot select a product or make a payment. This mode is only available on the desktop.",
--       user_account = 
--       {
--         payment_accounts = 
--         {
--           enable = true,
--         },
--         info = 
--         {
--           enable = true,
--           order = 123,
--         },
--         subscriptions = 
--         {
--           enable = true,
--           order = 123,
--         },
--       },
--       header = 
--       {
--         visible_virtual_currency_balance = true,
--       },
--       mobile = 
--       {
--         header = 
--         {
--           close_button = true,
--         },
--       },
--       is_prevent_external_link_open = true,
--       is_payment_methods_list_mode = true,
--       is_independent_windows = true,
--       currency_format = "Set to `code` to display a three-letter [ISO 4217](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/) currency code in the payment UI. The currency symbol is displayed instead of the three-letter currency code by default.",
--       is_show_close_widget_warning = true,
--       layout = "Location of the main elements of the payment UI. You can open the payment UI inside your game and/or swap the columns with information about an order and payment methods. Refer to the [customization instructions](https://developers.xsolla.com/doc/pay-station/features/ui-theme-customization/#pay_station_ui_theme_customization_layout) for detailed information.",
--       is_three_ds_independent_windows = true,
--       is_cart_open_by_default = true,
--     },
--     cart_payment_settings_payment_method = 123,
--     cart_payment_settings_return_url = "Page to redirect the user to after payment. Parameters `user_id`, `foreigninvoice`, `invoice_id` and `status` will be automatically added to the link.",
--     cart_payment_redirect_policy = 
--     {
--       redirect_conditions = "none",
--       delay = 0,
--       status_for_manual_redirection = "none",
--       redirect_button_caption = "Text button",
--     },
--   },
--   custom_parameters = 
--   {
--   },
-- }
function M.create_order_by_cart_id(project_id, cart_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/project/{project_id}/payment/cart/{cart_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "POST", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create order with all items from current cart
-- Used for client-to-server integration. Creates an order with all items from the cart and generates a payment token for it. The created order gets the `new` order status.
-- 
-- The client IP is used to determine the user’s country, which is then used to apply the corresponding currency and available payment methods for the order.
-- 
-- To open the payment UI in a new window, use the following link: `https://secure.xsolla.com/paystation4/?token={token}`, where `{token}` is the received token.
-- 
-- For testing purposes, use this URL: `https://sandbox-secure.xsolla.com/paystation4/?token={token}`.
-- 
-- Notice 
--  As this method uses the IP to determine the user’s country and select a currency for the order, it is important to only use this method from the client side and not from the server side. Using this method from the server side may cause incorrect currency determination and affect payment methods in Pay Station. 
-- @path /v2/project/{project_id}/payment/cart
-- @name create_order
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   currency = "Order price currency. Three-letter currency code per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). Check the documentation for detailed information about [currencies supported by Xsolla](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/).",
--   locale = "Response language.",
--   sandbox = true,
--   settings = 
--   {
--     cart_payment_settings_ui = 
--     {
--       theme = "Payment UI theme. Can be `63295a9a2e47fab76f7708e1` for the light theme (default) or `63295aab2e47fab76f7708e3` for the dark theme. You can also [create a custom theme](https://developers.xsolla.com/doc/pay-station/features/ui-theme-customization/#pay_station_ui_theme_customization_in_token) and pass its ID in this parameter.",
--       desktop = 
--       {
--         header = 
--         {
--           is_visible = true,
--           visible_logo = true,
--           visible_name = true,
--           visible_purchase = true,
--           type = "How to show the header. Can be `compact` (hides project name and user ID) or `normal` (default).",
--           close_button = true,
--         },
--       },
--       mode = "Interface mode in payment UI. Can be `user_account` only. The header contains only the account navigation menu, and the user cannot select a product or make a payment. This mode is only available on the desktop.",
--       user_account = 
--       {
--         payment_accounts = 
--         {
--           enable = true,
--         },
--         info = 
--         {
--           enable = true,
--           order = 123,
--         },
--         subscriptions = 
--         {
--           enable = true,
--           order = 123,
--         },
--       },
--       header = 
--       {
--         visible_virtual_currency_balance = true,
--       },
--       mobile = 
--       {
--         header = 
--         {
--           close_button = true,
--         },
--       },
--       is_prevent_external_link_open = true,
--       is_payment_methods_list_mode = true,
--       is_independent_windows = true,
--       currency_format = "Set to `code` to display a three-letter [ISO 4217](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/) currency code in the payment UI. The currency symbol is displayed instead of the three-letter currency code by default.",
--       is_show_close_widget_warning = true,
--       layout = "Location of the main elements of the payment UI. You can open the payment UI inside your game and/or swap the columns with information about an order and payment methods. Refer to the [customization instructions](https://developers.xsolla.com/doc/pay-station/features/ui-theme-customization/#pay_station_ui_theme_customization_layout) for detailed information.",
--       is_three_ds_independent_windows = true,
--       is_cart_open_by_default = true,
--     },
--     cart_payment_settings_payment_method = 123,
--     cart_payment_settings_return_url = "Page to redirect the user to after payment. Parameters `user_id`, `foreigninvoice`, `invoice_id` and `status` will be automatically added to the link.",
--     cart_payment_redirect_policy = 
--     {
--       redirect_conditions = "none",
--       delay = 0,
--       status_for_manual_redirection = "none",
--       redirect_button_caption = "Text button",
--     },
--   },
--   custom_parameters = 
--   {
--   },
-- }
function M.create_order(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/payment/cart"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "POST", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create order with specified item
-- Used for client-to-server integration. Creates an order with a specified item and generates a payment token for it. The created order gets the `new` order status.
-- 
-- The client IP is used to determine the user’s country, which is then used to apply the corresponding currency and available payment methods for the order.
-- 
-- To open the payment UI in a new window, use the following link: `https://secure.xsolla.com/paystation4/?token={token}`, where `{token}` is the received token.
-- 
-- For testing purposes, use this URL: `https://sandbox-secure.xsolla.com/paystation4/?token={token}`.
-- 
-- Notice 
--  As this method uses the IP to determine the user’s country and select a currency for the order, it is important to only use this method from the client side and not from the server side. Using this method from the server side may cause incorrect currency determination and affect payment methods in Pay Station. 
-- @path /v2/project/{project_id}/payment/item/{item_sku}
-- @name create_order_with_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   currency = "Order price currency. Three-letter currency code per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). Check the documentation for detailed information about [currencies supported by Xsolla](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/).",
--   locale = "Response language.",
--   sandbox = true,
--   quantity = 123,
--   promo_code = "Redeems a code of a promo code promotion with payment.",
--   settings = 
--   {
--     cart_payment_settings_ui = 
--     {
--       theme = "Payment UI theme. Can be `63295a9a2e47fab76f7708e1` for the light theme (default) or `63295aab2e47fab76f7708e3` for the dark theme. You can also [create a custom theme](https://developers.xsolla.com/doc/pay-station/features/ui-theme-customization/#pay_station_ui_theme_customization_in_token) and pass its ID in this parameter.",
--       desktop = 
--       {
--         header = 
--         {
--           is_visible = true,
--           visible_logo = true,
--           visible_name = true,
--           visible_purchase = true,
--           type = "How to show the header. Can be `compact` (hides project name and user ID) or `normal` (default).",
--           close_button = true,
--         },
--       },
--       mode = "Interface mode in payment UI. Can be `user_account` only. The header contains only the account navigation menu, and the user cannot select a product or make a payment. This mode is only available on the desktop.",
--       user_account = 
--       {
--         payment_accounts = 
--         {
--           enable = true,
--         },
--         info = 
--         {
--           enable = true,
--           order = 123,
--         },
--         subscriptions = 
--         {
--           enable = true,
--           order = 123,
--         },
--       },
--       header = 
--       {
--         visible_virtual_currency_balance = true,
--       },
--       mobile = 
--       {
--         header = 
--         {
--           close_button = true,
--         },
--       },
--       is_prevent_external_link_open = true,
--       is_payment_methods_list_mode = true,
--       is_independent_windows = true,
--       currency_format = "Set to `code` to display a three-letter [ISO 4217](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/) currency code in the payment UI. The currency symbol is displayed instead of the three-letter currency code by default.",
--       is_show_close_widget_warning = true,
--       layout = "Location of the main elements of the payment UI. You can open the payment UI inside your game and/or swap the columns with information about an order and payment methods. Refer to the [customization instructions](https://developers.xsolla.com/doc/pay-station/features/ui-theme-customization/#pay_station_ui_theme_customization_layout) for detailed information.",
--       is_three_ds_independent_windows = true,
--       is_cart_open_by_default = true,
--     },
--     cart_payment_settings_payment_method = 123,
--     cart_payment_settings_return_url = "Page to redirect the user to after payment. Parameters `user_id`, `foreigninvoice`, `invoice_id` and `status` will be automatically added to the link.",
--     cart_payment_redirect_policy = 
--     {
--       redirect_conditions = "none",
--       delay = 0,
--       status_for_manual_redirection = "none",
--       redirect_button_caption = "Text button",
--     },
--   },
--   custom_parameters = 
--   {
--   },
-- }
function M.create_order_with_item(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/payment/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "POST", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create order with free cart
-- Creates an order with all items from the free cart. The created order will get a `done` order status.
-- @path /v2/project/{project_id}/free/cart
-- @name create_free_order
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   currency = "Order price currency. Three-letter currency code per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). Check the documentation for detailed information about [currencies supported by Xsolla](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/).",
--   locale = "Response language.",
--   sandbox = true,
--   settings = 
--   {
--     cart_payment_settings_ui = 
--     {
--       theme = "Payment UI theme. Can be `63295a9a2e47fab76f7708e1` for the light theme (default) or `63295aab2e47fab76f7708e3` for the dark theme. You can also [create a custom theme](https://developers.xsolla.com/doc/pay-station/features/ui-theme-customization/#pay_station_ui_theme_customization_in_token) and pass its ID in this parameter.",
--       desktop = 
--       {
--         header = 
--         {
--           is_visible = true,
--           visible_logo = true,
--           visible_name = true,
--           visible_purchase = true,
--           type = "How to show the header. Can be `compact` (hides project name and user ID) or `normal` (default).",
--           close_button = true,
--         },
--       },
--       mode = "Interface mode in payment UI. Can be `user_account` only. The header contains only the account navigation menu, and the user cannot select a product or make a payment. This mode is only available on the desktop.",
--       user_account = 
--       {
--         payment_accounts = 
--         {
--           enable = true,
--         },
--         info = 
--         {
--           enable = true,
--           order = 123,
--         },
--         subscriptions = 
--         {
--           enable = true,
--           order = 123,
--         },
--       },
--       header = 
--       {
--         visible_virtual_currency_balance = true,
--       },
--       mobile = 
--       {
--         header = 
--         {
--           close_button = true,
--         },
--       },
--       is_prevent_external_link_open = true,
--       is_payment_methods_list_mode = true,
--       is_independent_windows = true,
--       currency_format = "Set to `code` to display a three-letter [ISO 4217](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/) currency code in the payment UI. The currency symbol is displayed instead of the three-letter currency code by default.",
--       is_show_close_widget_warning = true,
--       layout = "Location of the main elements of the payment UI. You can open the payment UI inside your game and/or swap the columns with information about an order and payment methods. Refer to the [customization instructions](https://developers.xsolla.com/doc/pay-station/features/ui-theme-customization/#pay_station_ui_theme_customization_layout) for detailed information.",
--       is_three_ds_independent_windows = true,
--       is_cart_open_by_default = true,
--     },
--     cart_payment_settings_payment_method = 123,
--     cart_payment_settings_return_url = "Page to redirect the user to after payment. Parameters `user_id`, `foreigninvoice`, `invoice_id` and `status` will be automatically added to the link.",
--     cart_payment_redirect_policy = 
--     {
--       redirect_conditions = "none",
--       delay = 0,
--       status_for_manual_redirection = "none",
--       redirect_button_caption = "Text button",
--     },
--   },
--   custom_parameters = 
--   {
--   },
-- }
function M.create_free_order(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/free/cart"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "POST", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create order with particular free cart
-- Creates an order with all items from the particular free cart. The created order will get a `done` order status.
-- @path /v2/project/{project_id}/free/cart/{cart_id}
-- @name create_free_order_by_cart_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   currency = "Order price currency. Three-letter currency code per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). Check the documentation for detailed information about [currencies supported by Xsolla](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/).",
--   locale = "Response language.",
--   sandbox = true,
--   settings = 
--   {
--     cart_payment_settings_ui = 
--     {
--       theme = "Payment UI theme. Can be `63295a9a2e47fab76f7708e1` for the light theme (default) or `63295aab2e47fab76f7708e3` for the dark theme. You can also [create a custom theme](https://developers.xsolla.com/doc/pay-station/features/ui-theme-customization/#pay_station_ui_theme_customization_in_token) and pass its ID in this parameter.",
--       desktop = 
--       {
--         header = 
--         {
--           is_visible = true,
--           visible_logo = true,
--           visible_name = true,
--           visible_purchase = true,
--           type = "How to show the header. Can be `compact` (hides project name and user ID) or `normal` (default).",
--           close_button = true,
--         },
--       },
--       mode = "Interface mode in payment UI. Can be `user_account` only. The header contains only the account navigation menu, and the user cannot select a product or make a payment. This mode is only available on the desktop.",
--       user_account = 
--       {
--         payment_accounts = 
--         {
--           enable = true,
--         },
--         info = 
--         {
--           enable = true,
--           order = 123,
--         },
--         subscriptions = 
--         {
--           enable = true,
--           order = 123,
--         },
--       },
--       header = 
--       {
--         visible_virtual_currency_balance = true,
--       },
--       mobile = 
--       {
--         header = 
--         {
--           close_button = true,
--         },
--       },
--       is_prevent_external_link_open = true,
--       is_payment_methods_list_mode = true,
--       is_independent_windows = true,
--       currency_format = "Set to `code` to display a three-letter [ISO 4217](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/) currency code in the payment UI. The currency symbol is displayed instead of the three-letter currency code by default.",
--       is_show_close_widget_warning = true,
--       layout = "Location of the main elements of the payment UI. You can open the payment UI inside your game and/or swap the columns with information about an order and payment methods. Refer to the [customization instructions](https://developers.xsolla.com/doc/pay-station/features/ui-theme-customization/#pay_station_ui_theme_customization_layout) for detailed information.",
--       is_three_ds_independent_windows = true,
--       is_cart_open_by_default = true,
--     },
--     cart_payment_settings_payment_method = 123,
--     cart_payment_settings_return_url = "Page to redirect the user to after payment. Parameters `user_id`, `foreigninvoice`, `invoice_id` and `status` will be automatically added to the link.",
--     cart_payment_redirect_policy = 
--     {
--       redirect_conditions = "none",
--       delay = 0,
--       status_for_manual_redirection = "none",
--       redirect_button_caption = "Text button",
--     },
--   },
--   custom_parameters = 
--   {
--   },
-- }
function M.create_free_order_by_cart_id(project_id, cart_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/project/{project_id}/free/cart/{cart_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "POST", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create order with specified free item
-- Creates an order with a specified free item. The created order will get a `done` order status.
-- @path /v2/project/{project_id}/free/item/{item_sku}
-- @name create_free_order_with_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   currency = "Order price currency. Three-letter currency code per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). Check the documentation for detailed information about [currencies supported by Xsolla](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/).",
--   locale = "Response language.",
--   sandbox = true,
--   quantity = 123,
--   promo_code = "Redeems a code of a promo code promotion with payment.",
--   settings = 
--   {
--     cart_payment_settings_ui = 
--     {
--       theme = "Payment UI theme. Can be `63295a9a2e47fab76f7708e1` for the light theme (default) or `63295aab2e47fab76f7708e3` for the dark theme. You can also [create a custom theme](https://developers.xsolla.com/doc/pay-station/features/ui-theme-customization/#pay_station_ui_theme_customization_in_token) and pass its ID in this parameter.",
--       desktop = 
--       {
--         header = 
--         {
--           is_visible = true,
--           visible_logo = true,
--           visible_name = true,
--           visible_purchase = true,
--           type = "How to show the header. Can be `compact` (hides project name and user ID) or `normal` (default).",
--           close_button = true,
--         },
--       },
--       mode = "Interface mode in payment UI. Can be `user_account` only. The header contains only the account navigation menu, and the user cannot select a product or make a payment. This mode is only available on the desktop.",
--       user_account = 
--       {
--         payment_accounts = 
--         {
--           enable = true,
--         },
--         info = 
--         {
--           enable = true,
--           order = 123,
--         },
--         subscriptions = 
--         {
--           enable = true,
--           order = 123,
--         },
--       },
--       header = 
--       {
--         visible_virtual_currency_balance = true,
--       },
--       mobile = 
--       {
--         header = 
--         {
--           close_button = true,
--         },
--       },
--       is_prevent_external_link_open = true,
--       is_payment_methods_list_mode = true,
--       is_independent_windows = true,
--       currency_format = "Set to `code` to display a three-letter [ISO 4217](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/) currency code in the payment UI. The currency symbol is displayed instead of the three-letter currency code by default.",
--       is_show_close_widget_warning = true,
--       layout = "Location of the main elements of the payment UI. You can open the payment UI inside your game and/or swap the columns with information about an order and payment methods. Refer to the [customization instructions](https://developers.xsolla.com/doc/pay-station/features/ui-theme-customization/#pay_station_ui_theme_customization_layout) for detailed information.",
--       is_three_ds_independent_windows = true,
--       is_cart_open_by_default = true,
--     },
--     cart_payment_settings_payment_method = 123,
--     cart_payment_settings_return_url = "Page to redirect the user to after payment. Parameters `user_id`, `foreigninvoice`, `invoice_id` and `status` will be automatically added to the link.",
--     cart_payment_redirect_policy = 
--     {
--       redirect_conditions = "none",
--       delay = 0,
--       status_for_manual_redirection = "none",
--       redirect_button_caption = "Text button",
--     },
--   },
--   custom_parameters = 
--   {
--   },
-- }
function M.create_free_order_with_item(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/free/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "POST", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get order
-- Retrieves a specified order.
-- @path /v2/project/{project_id}/order/{order_id}
-- @name get_order
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param order_id (REQUIRED) Order ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_order(project_id, order_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(order_id)

    local url_path = "/v2/project/{project_id}/order/{order_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{order_id}", uri.encode(tostring(order_id)))

    local query_params = {}

    local post_data = nil

    local headers = {}
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get list of upsell items in project
-- Gets a list of upsell items in a project if they have already been set up.
-- @path /v2/project/{project_id}/items/upsell
-- @name get_upsell_for_project_client
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_upsell_for_project_client(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/upsell"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get games list
-- Gets a games list for building a catalog.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
-- Note
-- In general, the use of catalog of items is available without authorization.
-- Only authorized users can get a personalized catalog.
-- @path /v2/project/{project_id}/items/game
-- @name get_games_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_games_list(project_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/game"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get games list by specified group
-- Gets a games list from the specified group for building a catalog.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
-- Note
-- In general, the use of catalog of items is available without authorization.
-- Only authorized users can get a personalized catalog.
-- @path /v2/project/{project_id}/items/game/group/{external_id}
-- @name get_games_group
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Group external ID.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_games_group(project_id, external_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/items/game/group/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get game for catalog
-- Gets a game for the catalog.
-- 
-- Note
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- @path /v2/project/{project_id}/items/game/sku/{item_sku}
-- @name get_game_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_game_by_sku(project_id, item_sku, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/items/game/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get game key for catalog
-- Gets a game key for the catalog.
-- 
-- Note
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- @path /v2/project/{project_id}/items/game/key/sku/{item_sku}
-- @name get_game_key_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_game_key_by_sku(project_id, item_sku, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/items/game/key/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get game keys list by specified group
-- Gets a game key list from the specified group for building a catalog.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
-- Note
-- In general, the use of catalog of items is available without authorization.
-- Only authorized users can get a personalized catalog.
-- @path /v2/project/{project_id}/items/game/key/group/{external_id}
-- @name get_game_keys_group
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Group external ID.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_game_keys_group(project_id, external_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/items/game/key/group/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get DRM list
-- Gets the list of available DRMs.
-- @path /v2/project/{project_id}/items/game/drm
-- @name get_drm_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_drm_list(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/game/drm"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    local headers = {}

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get list of games owned by user
-- Get the list of games owned by the user. The response will contain an array of games owned by a particular user.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields.
-- @path /v2/project/{project_id}/entitlement
-- @name get_user_games
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param sandbox What type of entitlements should be returned. If the parameter is set to 1, the entitlements received by the user in the sandbox mode only are returned. If the parameter isn&#x27;t passed or is set to 0, the entitlements received by the user in the live mode only are returned.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request. Available fields `attributes`.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_user_games(project_id, limit, offset, sandbox, additional_fields, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/entitlement"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["sandbox"] = sandbox
    query_params["additional_fields"] = additional_fields

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Redeem game code by client
-- Grants entitlement by a provided game code.
-- 
-- Attention
-- You can redeem codes only for the DRM-free platform.
-- @path /v2/project/{project_id}/entitlement/redeem
-- @name redeem_game_pin_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   code = "AAAA-BBBB-CCCC-DDDD",
--   sandbox = false,
-- }
function M.redeem_game_pin_code(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/entitlement/redeem"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "POST", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get physical items list
-- Gets a physical items list for building a catalog.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
-- Note
-- In general, the use of catalog of items is available without authorization.
-- Only authorized users can get a personalized catalog.
-- @path /v2/project/{project_id}/items/physical_good
-- @name get_physical_goods_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_physical_goods_list(project_id, limit, offset, locale, additional_fields, country, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/physical_good"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update physical item
-- Updates a physical item.
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/physical_good/id/{item_id}
-- @path /v2/project/{project_id}/admin/items/physical_good/sku/{item_sku}
-- @name admin_update_physical_item_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note Xsolla API uses basic access authentication. All requests to API must
-- contain the `Authorization: Basic `
-- header, where `your_authorization_basic_key` is the `project_id:api_key`
-- pair encoded according to the Base64 standard.
-- 
-- You can use `merchant_id` instead of `project_id` if you need. It doesn&#x27;t affect functionality.
-- 
-- Go to [Publisher Account](https://publisher.xsolla.com/) to find values of the parameters:
-- 
-- * `merchant_id` is shown:
--   * In the **Company settings &gt; Company** section
--   * In the URL in the browser address bar on any Publisher Account page. The URL has the following format: `https://publisher.xsolla.com/`.
-- * `api_key` is shown in Publisher Account only once when it is created and must be stored on your side. You can create a new key in the following section:
--   * **Company settings &gt; API keys**
--   * **Project settings &gt; API keys**
-- * `project_id` is shown:
--   * In Publisher Account next to the name of the project.
--   * In the URL in the browser address bar when working on project in Publisher Account. The URL has the following format: `https://publisher.xsolla.com//projects/`.
-- 
-- For more information about working with API keys, see the [API reference](https://developers.xsolla.com/api/getting-started/#api_keys_overview).
-- @example Request body example
-- {
--   sku = "",
--   name = 
--   {
--     en = "Item's name.",
--     ar = nil,
--     bg = nil,
--     cn = nil,
--     cs = nil,
--     de = "Name des Artikels.",
--     es = "Nombre del artículo.",
--     fr = "Nom de l'élément.",
--     he = nil,
--     it = "Nome dell'elemento.",
--     ja = "買い物の名前。",
--     ko = nil,
--     pl = nil,
--     pt = nil,
--     ro = nil,
--     ru = nil,
--     th = nil,
--     tr = nil,
--     tw = nil,
--     vi = nil,
--   },
--   description = 
--   {
--     en = "Item's description.",
--     ar = nil,
--     bg = nil,
--     cn = nil,
--     cs = nil,
--     de = "Artikelbeschreibung.",
--     es = "Descripción del artículo.",
--     fr = "Description de l'article.",
--     he = nil,
--     it = "Descrizione dell'oggetto.",
--     ja = "買い物の説明。",
--     ko = nil,
--     pl = nil,
--     pt = nil,
--     ro = nil,
--     ru = nil,
--     th = nil,
--     tr = nil,
--     tw = nil,
--     vi = nil,
--   },
--   long_description = 
--   {
--     en = "Long description of item.",
--     ar = nil,
--     bg = nil,
--     cn = nil,
--     cs = nil,
--     de = "Lange Beschreibung des Artikels.",
--     es = "Descripción larga del artículo.",
--     fr = "Description longue de l'article.",
--     he = nil,
--     it = "Descrizione lunga dell'articolo.",
--     ja = "アイテムの長い説明。",
--     ko = nil,
--     pl = nil,
--     pt = nil,
--     ro = nil,
--     ru = nil,
--     th = nil,
--     tr = nil,
--     tw = nil,
--     vi = nil,
--   },
--   image_url = "",
--   media_list = 
--   {
--     "",
--   },
--   groups = 
--   {
--     "",
--   },
--   attributes = 
--   {
--     {
--       admin_attribute_external_id = "attribute_1",
--       admin_attribute_name = 
--       {
--       },
--       values = 
--       {
--         {
--           value_external_id = "attribute_value",
--           value_name = 
--           {
--           },
--         },
--       },
--     },
--   },
--   prices = 
--   {
--     {
--       currency = "USD",
--       amount = 123.456,
--       is_default = true,
--       is_enabled = true,
--       country_iso = "US",
--     },
--   },
--   vc_prices = 
--   {
--     {
--       virtual_items_currency_schemas_sku = "bundle_1",
--       amount = 123,
--       is_default = true,
--       is_enabled = true,
--     },
--   },
--   is_enabled = true,
--   is_deleted = true,
--   is_free = false,
--   order = 123.456,
--   tax_categories = 
--   {
--     "",
--   },
--   pre_order = 
--   {
--     release_date = "",
--     is_enabled = true,
--     description = "",
--   },
--   regions = 
--   {
--     {
--       id = 1,
--     },
--   },
--   weight = 
--   {
--     grams = "874.5",
--     ounces = "3",
--   },
--   limits = 
--   {
--     per_user = 123,
--     per_item = 10,
--     recurrent_schedule = 
--     {
--       per_user = 
--       {
--         interval_type = "Recurrent refresh period.",
--         time = "02:00:00+03:00",
--       },
--     },
--   },
-- }
function M.admin_update_physical_item_by_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    headers["Authorization"] = authorization.basic

    return http(callback, url_path, query_params, "PUT", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Redeem coupon code
-- Redeems a coupon code. The user gets a bonus after a coupon is redeemed.
-- @path /v2/project/{project_id}/coupon/redeem
-- @name redeem_coupon
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   coupon_code = "WINTER2021",
--   selected_unit_items = 
--   {
--   },
-- }
function M.redeem_coupon(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/coupon/redeem"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "POST", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get coupon rewards
-- Gets coupons rewards by its code.
-- Can be used to allow users to choose one of many items as a bonus.
-- The usual case is choosing a DRM if the coupon contains a game as a bonus (`type=unit`).
-- @path /v2/project/{project_id}/coupon/code/{coupon_code}/rewards
-- @name get_coupon_rewards_by_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param coupon_code (REQUIRED) Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_coupon_rewards_by_code(project_id, coupon_code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(coupon_code)

    local url_path = "/v2/project/{project_id}/coupon/code/{coupon_code}/rewards"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{coupon_code}", uri.encode(tostring(coupon_code)))

    local query_params = {}

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Redeem promo code
-- Redeems a code of promo code promotion.
-- After redeeming a promo code, the user will get free items and/or the price of the cart and/or particular items will be decreased.
-- @path /v2/project/{project_id}/promocode/redeem
-- @name redeem_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   coupon_code = "SUMMER2021",
--   cart = 
--   {
--     id = "Cart ID.",
--   },
--   selected_unit_items = 
--   {
--   },
-- }
function M.redeem_promo_code(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/promocode/redeem"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "POST", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Remove promo code from cart
-- Removes a promo code from a cart.
-- After the promo code is removed, the total price of all items in the cart will be recalculated without bonuses and discounts provided by a promo code.
-- @path /v2/project/{project_id}/promocode/remove
-- @name remove_cart_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note When selling a cart with games, you can [call the endpoint without authorization](/doc/buy-button/how-to/set-up-authentication/#guides_buy_button_selling_items_not_authenticated_users).
-- 
-- To do this:
-- 
-- * Add a unique identifier to the `x-unauthorized-id` parameter in the header for games.
-- * Add user’s email to the `x-user` parameter (Base64 encoded) in the header for games.
-- 
-- By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   cart = 
--   {
--     id = "Cart ID.",
--   },
-- }
function M.remove_cart_promo_code(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/promocode/remove"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    if authorization.x_unauthorized_id then
        headers["x-unauthorized-id"] = authorization.x_unauthorized_id
        headers["x-user"] = authorization.x_user
    else
        headers["Authorization"] = authorization.bearer
    end

    return http(callback, url_path, query_params, "PUT", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get promo code reward
-- Gets promo code rewards by its code.
-- Can be used to allow users to choose one of many items as a bonus.
-- The usual case is choosing a DRM if the promo code contains a game as a bonus (`type=unit`).
-- @path /v2/project/{project_id}/promocode/code/{promocode_code}/rewards
-- @name get_promo_code_rewards_by_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promocode_code (REQUIRED) Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_promo_code_rewards_by_code(project_id, promocode_code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(promocode_code)

    local url_path = "/v2/project/{project_id}/promocode/code/{promocode_code}/rewards"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promocode_code}", uri.encode(tostring(promocode_code)))

    local query_params = {}

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Verify promotion code
-- Determines if the code is a promo code or coupon code and if the user can apply it.
-- @path /v2/project/{project_id}/promotion/code/{code}/verify
-- @name verify_promotion_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param code (REQUIRED) Unique case-sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.verify_promotion_code(project_id, code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(code)

    local url_path = "/v2/project/{project_id}/promotion/code/{code}/verify"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{code}", uri.encode(tostring(code)))

    local query_params = {}

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get virtual items list
-- Gets a virtual items list for building a catalog.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
-- Note
-- In general, the use of catalog of items is available without authorization.
-- Only authorized users can get a personalized catalog.
-- @path /v2/project/{project_id}/items/virtual_items
-- @name get_virtual_items
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_virtual_items(project_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/virtual_items"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get virtual item by SKU
-- Gets a virtual item by SKU for building a catalog.
-- Note
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- @path /v2/project/{project_id}/items/virtual_items/sku/{item_sku}
-- @name get_virtual_items_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_virtual_items_sku(project_id, item_sku, locale, country, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/items/virtual_items/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}
    query_params["locale"] = locale
    query_params["country"] = country
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get all virtual items list
-- Gets a list of all virtual items for searching on client-side.
-- 
-- Attention
-- Returns only item SKU, name, groups and description 
-- Note
-- In general, the use of catalog of items is available without authorization.
-- Only authorized users can get a personalized catalog.
-- @path /v2/project/{project_id}/items/virtual_items/all
-- @name get_all_virtual_items
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_all_virtual_items(project_id, locale, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/virtual_items/all"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["locale"] = locale
    query_params["promo_code"] = promo_code

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get virtual currency list
-- Gets a virtual currency list for building a catalog.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
-- Note
-- In general, the use of catalog of items is available without authorization.
-- Only authorized users can get a personalized catalog.
-- @path /v2/project/{project_id}/items/virtual_currency
-- @name get_virtual_currency
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_virtual_currency(project_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/virtual_currency"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get virtual currency by SKU
-- Gets a virtual currency by SKU for building a catalog.
-- Note
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- @path /v2/project/{project_id}/items/virtual_currency/sku/{virtual_currency_sku}
-- @name get_virtual_currency_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param virtual_currency_sku (REQUIRED) Virtual currency SKU.
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_virtual_currency_sku(project_id, virtual_currency_sku, locale, country, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(virtual_currency_sku)

    local url_path = "/v2/project/{project_id}/items/virtual_currency/sku/{virtual_currency_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{virtual_currency_sku}", uri.encode(tostring(virtual_currency_sku)))

    local query_params = {}
    query_params["locale"] = locale
    query_params["country"] = country
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get virtual currency package list
-- Gets a virtual currency packages list for building a catalog.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
-- Note
-- In general, the use of catalog of items is available without authorization.
-- Only authorized users can get a personalized catalog.
-- @path /v2/project/{project_id}/items/virtual_currency/package
-- @name get_virtual_currency_package
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_virtual_currency_package(project_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/virtual_currency/package"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get virtual currency package by SKU
-- Gets a virtual currency packages by SKU for building a catalog.
-- Note
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- @path /v2/project/{project_id}/items/virtual_currency/package/sku/{virtual_currency_package_sku}
-- @name get_virtual_currency_package_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param virtual_currency_package_sku (REQUIRED) Virtual currency package SKU.
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_virtual_currency_package_sku(project_id, virtual_currency_package_sku, locale, country, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(virtual_currency_package_sku)

    local url_path = "/v2/project/{project_id}/items/virtual_currency/package/sku/{virtual_currency_package_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{virtual_currency_package_sku}", uri.encode(tostring(virtual_currency_package_sku)))

    local query_params = {}
    query_params["locale"] = locale
    query_params["country"] = country
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get items list by specified group
-- Gets an items list from the specified group for building a catalog.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
-- Note
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- @path /v2/project/{project_id}/items/virtual_items/group/{external_id}
-- @name get_virtual_items_group
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Group external ID.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_virtual_items_group(project_id, external_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/items/virtual_items/group/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get items groups list
-- Gets an items groups list for building a catalog.
-- @path /v2/project/{project_id}/items/groups
-- @name get_item_groups
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_item_groups(project_id, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/groups"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = nil

    local headers = {}

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create order with specified item purchased by virtual currency
-- Creates item purchase using virtual currency.
-- @path /v2/project/{project_id}/payment/item/{item_sku}/virtual/{virtual_currency_sku}
-- @name create_order_with_item_for_virtual_currency
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param virtual_currency_sku (REQUIRED) Virtual currency SKU.
-- @param platform Publishing platform the user plays on: `xsolla` (default), `playstation_network`, `xbox_live`, `pc_standalone`, `nintendo_shop`, `google_play`, `app_store_ios`, `android_standalone`, `ios_standalone`, `android_other`, `ios_other`, `pc_other`.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
-- @example Request body example
-- {
--   custom_parameters = 
--   {
--   },
-- }
function M.create_order_with_item_for_virtual_currency(project_id, item_sku, virtual_currency_sku, platform, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)
    assert(virtual_currency_sku)

    local url_path = "/v2/project/{project_id}/payment/item/{item_sku}/virtual/{virtual_currency_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))
    url_path = url_path:gsub("{virtual_currency_sku}", uri.encode(tostring(virtual_currency_sku)))

    local query_params = {}
    query_params["platform"] = platform

    local post_data = json.encode(body)

    local headers = {}
    headers["Content-Type"] = "application/json"
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "POST", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get sellable items list
-- Gets a sellable items list for building a catalog.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
-- Note
-- In general, the use of catalog of items is available without authorization.
-- Only authorized users can get a personalized catalog.
-- @path /v2/project/{project_id}/items
-- @name get_sellable_items
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_sellable_items(project_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get sellable item by ID
-- Gets a sellable item by its ID.
-- Note
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- @path /v2/project/{project_id}/items/id/{item_id}
-- @name get_sellable_item_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_sellable_item_by_id(project_id, item_id, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/items/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_id}", uri.encode(tostring(item_id)))

    local query_params = {}
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get sellable item by SKU
-- Gets a sellable item by SKU for building a catalog.
-- Note
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- @path /v2/project/{project_id}/items/sku/{sku}
-- @name get_sellable_item_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param sku (REQUIRED) Item SKU.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_sellable_item_by_sku(project_id, sku, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(sku)

    local url_path = "/v2/project/{project_id}/items/sku/{sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{sku}", uri.encode(tostring(sku)))

    local query_params = {}
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get sellable items list by specified group
-- Gets a sellable items list from the specified group for building a catalog.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
-- Note
-- In general, the use of catalog of items is available without authorization.
-- Only authorized users can get a personalized catalog.
-- @path /v2/project/{project_id}/items/group/{external_id}
-- @name get_sellable_items_group
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Group external ID.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_sellable_items_group(project_id, external_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/items/group/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get current user&#x27;s reward chains
-- Client endpoint. Gets the current user’s reward chains.
-- 
-- Attention
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields.
-- @path /v2/project/{project_id}/user/reward_chain
-- @name get_reward_chains_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_reward_chains_list(project_id, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/user/reward_chain"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get current user&#x27;s value point balance
-- Client endpoint. Gets the current user’s value point balance.
-- @path /v2/project/{project_id}/user/reward_chain/{reward_chain_id}/balance
-- @name get_user_reward_chain_balance
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param reward_chain_id (REQUIRED) Reward chain ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_user_reward_chain_balance(project_id, reward_chain_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(reward_chain_id)

    local url_path = "/v2/project/{project_id}/user/reward_chain/{reward_chain_id}/balance"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(tostring(reward_chain_id)))

    local query_params = {}

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Claim step reward
-- Client endpoint. Claims the current user’s step reward from a reward chain.
-- @path /v2/project/{project_id}/user/reward_chain/{reward_chain_id}/step/{step_id}/claim
-- @name claim_user_reward_chain_step_reward
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param reward_chain_id (REQUIRED) Reward chain ID.
-- @param step_id (REQUIRED) Reward chain step ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.claim_user_reward_chain_step_reward(project_id, reward_chain_id, step_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(reward_chain_id)
    assert(step_id)

    local url_path = "/v2/project/{project_id}/user/reward_chain/{reward_chain_id}/step/{step_id}/claim"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(tostring(reward_chain_id)))
    url_path = url_path:gsub("{step_id}", uri.encode(tostring(step_id)))

    local query_params = {}

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "POST", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get top 10 contributors to reward chain under clan
-- Retrieves the list of top 10 contributors to the specific reward chain under the current user&#x27;s clan. If a user doesn&#x27;t belong to a clan, the call returns an empty array.
-- @path /v2/project/{project_id}/user/clan/contributors/{reward_chain_id}/top
-- @name get_user_clan_top_contributors
-- @param project_id (REQUIRED) Project ID.
-- @param reward_chain_id (REQUIRED) Reward chain ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.get_user_clan_top_contributors(project_id, reward_chain_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(reward_chain_id)

    local url_path = "/v2/project/{project_id}/user/clan/contributors/{reward_chain_id}/top"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(tostring(reward_chain_id)))

    local query_params = {}

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "GET", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update current user&#x27;s clan
-- Updates a current user&#x27;s clan via user attributes. Claims all rewards from reward chains that were not claimed for a previous clan and returns them in the response. If the user was in a clan and now is not — their inclusion in the clan will be revoked. If the user changed the clan — the clan will be changed.
-- @path /v2/project/{project_id}/user/clan/update
-- @name user_clan_update
-- @param project_id (REQUIRED) Project ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
-- @note By default, the Xsolla Login User JWT (Bearer token) is used for authorization. You can try calling this endpoint with a test Xsolla Login User JWT token: `Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5NjIyMzQwNDgsImlzcyI6Imh0dHBzOi8vbG9naW4ueHNvbGxhLmNvbSIsImlhdCI6MTU2MjE0NzY0OCwidXNlcm5hbWUiOiJ4c29sbGEiLCJ4c29sbGFfbG9naW5fYWNjZXNzX2tleSI6IjA2SWF2ZHpDeEVHbm5aMTlpLUc5TmMxVWFfTWFZOXhTR3ZEVEY4OFE3RnMiLCJzdWIiOiJkMzQyZGFkMi05ZDU5LTExZTktYTM4NC00MjAxMGFhODAwM2YiLCJlbWFpbCI6InN1cHBvcnRAeHNvbGxhLmNvbSIsInR5cGUiOiJ4c29sbGFfbG9naW4iLCJ4c29sbGFfbG9naW5fcHJvamVjdF9pZCI6ImU2ZGZhYWM2LTc4YTgtMTFlOS05MjQ0LTQyMDEwYWE4MDAwNCIsInB1Ymxpc2hlcl9pZCI6MTU5MjR9.GCrW42OguZbLZTaoixCZgAeNLGH2xCeJHxl8u8Xn2aI`.
-- 
-- You can use the [Pay Station access token](https://developers.xsolla.com/api/pay-station/operation/create-token/) as an alternative.
function M.user_clan_update(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/user/clan/update"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    local headers = {}
    headers["Authorization"] = authorization.bearer

    return http(callback, url_path, query_params, "PUT", headers, post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

return M