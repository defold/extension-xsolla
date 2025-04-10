local log = require("xsolla.util.log")
local net = require("xsolla.util.net")
local uri = require("xsolla.util.uri")
local async = require("xsolla.util.async")
local retries = require("xsolla.util.retries")

local M = {}

local SERVERS = {
    "https://store.xsolla.com/api",
}


local config = {
    http_uri = SERVERS[1],
    bearer_token = nil,
    username = nil,
    password = nil,
    timeout = 3,    -- seconds
    retry_policy = retries.exponential(5, 0.5),
}

-- cancellation tokens associated with a coroutine
local cancellation_tokens = {}

-- cancel a cancellation token
function M.cancel(token)
    assert(token)
    token.cancelled = true
end

-- create a cancellation token
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

function M.set_bearer_token(bearer_token)
    config.bearer_token = bearer_token
end

-- Private
-- Run code within a coroutine
-- @param fn The code to run
-- @param cancellation_token Optional cancellation token to cancel the running code
function M.sync(fn, cancellation_token)
    assert(fn)
    local co = nil
    co = coroutine.create(function()
        cancellation_tokens[co] = cancellation_token
        fn()
        cancellation_tokens[co] = nil
    end)
    local ok, err = coroutine.resume(co)
    if not ok then
        log(err)
        cancellation_tokens[co] = nil
    end
end

-- http request helper used to reduce code duplication in all API functions below
local function http(callback, url_path, query_params, method, post_data, retry_policy, cancellation_token, handler_fn)
    if callback then
        log(url_path, "with callback")
        net.http(config, url_path, query_params, method, post_data, retry_policy, cancellation_token, function(result)
            if not cancellation_token or not cancellation_token.cancelled then
                callback(handler_fn(result))
            end
        end)
    else
        log(url_path, "with coroutine")
        local co = coroutine.running()
        assert(co, "You must be running this from withing a coroutine")

        -- get cancellation token associated with this coroutine
        cancellation_token = cancellation_tokens[co]
        if cancellation_token and cancellation_token.cancelled then
            cancellation_tokens[co] = nil
            return
        end

        return async(function(done)
            net.http(config, url_path, query_params, method, post_data, retry_policy, cancellation_token, function(result)
                if cancellation_token and cancellation_token.cancelled then
                    cancellation_tokens[co] = nil
                    return
                end
                done(handler_fn(result))
            end)
        end)
    end
end


function M.body_create_update_attribute(t)
    assert(t.external_id)
    assert(t.name)
    return json.encode({
        ["external_id"] = t.external_id,
        ["name"] = t.name,
  })
end


function M.body_create_update_attribute_value(t)
    assert(t.external_id)
    assert(t.value)
    return json.encode({
        ["external_id"] = t.external_id,
        ["value"] = t.value,
  })
end


function M.body_personalized_catalog_create_update_body(t)
    assert(t.name)
    assert(t.is_enabled)
    assert(t.attribute_conditions)
    assert(t.items)
    return json.encode({
        ["name"] = t.name,
        ["is_enabled"] = t.is_enabled,
        ["is_satisfied_for_unauth"] = t.is_satisfied_for_unauth,
        ["attribute_conditions"] = t.attribute_conditions,
        ["items"] = t.items,
  })
end


function M.body_bundles_bundle(t)
    assert(t.sku)
    assert(t.name)
    assert(t.description)
    return json.encode({
        ["sku"] = t.sku,
        ["name"] = t.name,
        ["groups"] = t.groups,
        ["attributes"] = t.attributes,
        ["description"] = t.description,
        ["long_description"] = t.long_description,
        ["image_url"] = t.image_url,
        ["prices"] = t.prices,
        ["vc_prices"] = t.vc_prices,
        ["content"] = t.content,
        ["is_free"] = t.is_free,
        ["is_enabled"] = t.is_enabled,
        ["is_show_in_store"] = t.is_show_in_store,
        ["media_list"] = t.media_list,
        ["order"] = t.order,
        ["regions"] = t.regions,
        ["limits"] = t.limits,
        ["periods"] = t.periods,
        ["custom_attributes"] = t.custom_attributes,
  })
end


function M.body_cart_payment_fill_cart_json_model(t)
    assert(t.items)
    return json.encode({
        ["items"] = t.items,
  })
end


function M.body_cart_payment_put_item_by_cart_idjsonmodel(t)
    return json.encode({
        ["quantity"] = t.quantity,
  })
end


function M.body_cart_payment_create_order_by_cart_idjsonmodel(t)
    return json.encode({
        ["currency"] = t.currency,
        ["locale"] = t.locale,
        ["sandbox"] = t.sandbox,
        ["settings"] = t.settings,
        ["custom_parameters"] = t.custom_parameters,
  })
end


function M.body_cart_payment_create_order_with_specified_item_idjsonmodel(t)
    return json.encode({
        ["currency"] = t.currency,
        ["locale"] = t.locale,
        ["sandbox"] = t.sandbox,
        ["quantity"] = t.quantity,
        ["promo_code"] = t.promo_code,
        ["settings"] = t.settings,
        ["custom_parameters"] = t.custom_parameters,
  })
end


function M.body_admin_order_search(t)
    return json.encode({
        ["limit"] = t.limit,
        ["offset"] = t.offset,
        ["created_date_from"] = t.created_date_from,
        ["created_date_until"] = t.created_date_until,
  })
end


function M.body_cart_payment_admin_create_payment_token(t)
    assert(t.user)
    assert(t.purchase)
    return json.encode({
        ["sandbox"] = t.sandbox,
        ["user"] = t.user,
        ["purchase"] = t.purchase,
        ["settings"] = t.settings,
        ["custom_parameters"] = t.custom_parameters,
  })
end


function M.body_cart_payment_admin_fill_cart_json_model(t)
    assert(t.items)
    return json.encode({
        ["country"] = t.country,
        ["currency"] = t.currency,
        ["items"] = t.items,
  })
end


function M.body_update_upsell(t)
    return json.encode({
  })
end


function M.body_create_upsell(t)
    return json.encode({
  })
end


function M.body_game_keys_create_update_game_model(t)
    assert(t.sku)
    assert(t.name)
    assert(t.unit_items)
    return json.encode({
        ["sku"] = t.sku,
        ["name"] = t.name,
        ["description"] = t.description,
        ["long_description"] = t.long_description,
        ["image_url"] = t.image_url,
        ["media_list"] = t.media_list,
        ["order"] = t.order,
        ["groups"] = t.groups,
        ["attributes"] = t.attributes,
        ["is_enabled"] = t.is_enabled,
        ["is_show_in_store"] = t.is_show_in_store,
        ["unit_items"] = t.unit_items,
  })
end


function M.body_physical_items_create_update_physical_good_model(t)
    assert(t.sku)
    return json.encode({
        ["sku"] = t.sku,
        ["name"] = t.name,
        ["description"] = t.description,
        ["long_description"] = t.long_description,
        ["image_url"] = t.image_url,
        ["media_list"] = t.media_list,
        ["groups"] = t.groups,
        ["attributes"] = t.attributes,
        ["prices"] = t.prices,
        ["vc_prices"] = t.vc_prices,
        ["is_enabled"] = t.is_enabled,
        ["is_deleted"] = t.is_deleted,
        ["is_free"] = t.is_free,
        ["order"] = t.order,
        ["tax_categories"] = t.tax_categories,
        ["pre_order"] = t.pre_order,
        ["regions"] = t.regions,
        ["weight"] = t.weight,
        ["limits"] = t.limits,
  })
end


function M.body_physical_items_patch_physical_good_model(t)
    assert(t.True)
    return json.encode({
        ["sku"] = t.sku,
        ["name"] = t.name,
        ["description"] = t.description,
        ["long_description"] = t.long_description,
        ["image_url"] = t.image_url,
        ["media_list"] = t.media_list,
        ["groups"] = t.groups,
        ["attributes"] = t.attributes,
        ["prices"] = t.prices,
        ["vc_prices"] = t.vc_prices,
        ["is_enabled"] = t.is_enabled,
        ["is_deleted"] = t.is_deleted,
        ["is_free"] = t.is_free,
        ["order"] = t.order,
        ["tax_categories"] = t.tax_categories,
        ["pre_order"] = t.pre_order,
        ["regions"] = t.regions,
        ["weight"] = t.weight,
        ["limits"] = t.limits,
  })
end


function M.body_promotions_redeem_coupon_model(t)
    return json.encode({
        ["coupon_code"] = t.coupon_code,
        ["selected_unit_items"] = t.selected_unit_items,
  })
end


function M.body_promotions_coupon_create(t)
    assert(t.external_id)
    assert(t.name)
    return json.encode({
        ["external_id"] = t.external_id,
        ["date_start"] = t.date_start,
        ["date_end"] = t.date_end,
        ["name"] = t.name,
        ["bonus"] = t.bonus,
        ["redeem_total_limit"] = t.redeem_total_limit,
        ["redeem_user_limit"] = t.redeem_user_limit,
        ["redeem_code_limit"] = t.redeem_code_limit,
        ["attribute_conditions"] = t.attribute_conditions,
  })
end


function M.body_promotions_coupon_update(t)
    assert(t.name)
    return json.encode({
        ["date_start"] = t.date_start,
        ["date_end"] = t.date_end,
        ["name"] = t.name,
        ["bonus"] = t.bonus,
        ["redeem_total_limit"] = t.redeem_total_limit,
        ["redeem_user_limit"] = t.redeem_user_limit,
        ["redeem_code_limit"] = t.redeem_code_limit,
        ["attribute_conditions"] = t.attribute_conditions,
  })
end


function M.body_promotions_create_coupon_promocode_code(t)
    return json.encode({
        ["coupon_code"] = t.coupon_code,
  })
end


function M.body_promotions_redeem_promo_code_model(t)
    return json.encode({
        ["coupon_code"] = t.coupon_code,
        ["cart"] = t.cart,
        ["selected_unit_items"] = t.selected_unit_items,
  })
end


function M.body_promotions_cancel_promo_code_model(t)
    return json.encode({
        ["cart"] = t.cart,
  })
end


function M.body_promotions_promocode_create(t)
    assert(t.external_id)
    assert(t.name)
    return json.encode({
        ["external_id"] = t.external_id,
        ["date_start"] = t.date_start,
        ["date_end"] = t.date_end,
        ["name"] = t.name,
        ["bonus"] = t.bonus,
        ["redeem_total_limit"] = t.redeem_total_limit,
        ["redeem_user_limit"] = t.redeem_user_limit,
        ["redeem_code_limit"] = t.redeem_code_limit,
        ["discount"] = t.discount,
        ["discounted_items"] = t.discounted_items,
        ["attribute_conditions"] = t.attribute_conditions,
        ["price_conditions"] = t.price_conditions,
        ["item_price_conditions"] = t.item_price_conditions,
        ["excluded_promotions"] = t.excluded_promotions,
  })
end


function M.body_promotions_promocode_update(t)
    assert(t.external_id)
    assert(t.name)
    return json.encode({
        ["date_start"] = t.date_start,
        ["date_end"] = t.date_end,
        ["name"] = t.name,
        ["bonus"] = t.bonus,
        ["redeem_total_limit"] = t.redeem_total_limit,
        ["redeem_user_limit"] = t.redeem_user_limit,
        ["redeem_code_limit"] = t.redeem_code_limit,
        ["discount"] = t.discount,
        ["discounted_items"] = t.discounted_items,
        ["attribute_conditions"] = t.attribute_conditions,
        ["price_conditions"] = t.price_conditions,
        ["item_price_conditions"] = t.item_price_conditions,
        ["excluded_promotions"] = t.excluded_promotions,
  })
end


function M.body_promotions_create_update_item_promotion(t)
    assert(t.items)
    assert(t.discount)
    assert(t.name)
    return json.encode({
        ["name"] = t.name,
        ["date_start"] = t.date_start,
        ["date_end"] = t.date_end,
        ["discount"] = t.discount,
        ["items"] = t.items,
        ["attribute_conditions"] = t.attribute_conditions,
        ["price_conditions"] = t.price_conditions,
        ["limits"] = t.limits,
        ["excluded_promotions"] = t.excluded_promotions,
  })
end


function M.body_promotions_create_update_bonus_promotion(t)
    assert(t.condition)
    assert(t.bonus)
    assert(t.name)
    return json.encode({
        ["id"] = t.id,
        ["date_start"] = t.date_start,
        ["date_end"] = t.date_end,
        ["name"] = t.name,
        ["condition"] = t.condition,
        ["attribute_conditions"] = t.attribute_conditions,
        ["bonus"] = t.bonus,
        ["limits"] = t.limits,
        ["price_conditions"] = t.price_conditions,
        ["excluded_promotions"] = t.excluded_promotions,
  })
end


function M.body_virtual_items_currency_admin_create_virtual_item(t)
    return json.encode({
        ["sku"] = t.sku,
        ["name"] = t.name,
        ["description"] = t.description,
        ["long_description"] = t.long_description,
        ["image_url"] = t.image_url,
        ["media_list"] = t.media_list,
        ["groups"] = t.groups,
        ["attributes"] = t.attributes,
        ["prices"] = t.prices,
        ["vc_prices"] = t.vc_prices,
        ["is_enabled"] = t.is_enabled,
        ["is_deleted"] = t.is_deleted,
        ["is_show_in_store"] = t.is_show_in_store,
        ["is_free"] = t.is_free,
        ["order"] = t.order,
        ["inventory_options"] = t.inventory_options,
        ["pre_order"] = t.pre_order,
        ["regions"] = t.regions,
        ["limits"] = t.limits,
        ["periods"] = t.periods,
        ["custom_attributes"] = t.custom_attributes,
  })
end


function M.body_virtual_items_currency_admin_create_virtual_currency(t)
    assert(t.sku)
    assert(t.name)
    return json.encode({
        ["sku"] = t.sku,
        ["name"] = t.name,
        ["description"] = t.description,
        ["long_description"] = t.long_description,
        ["image_url"] = t.image_url,
        ["media_list"] = t.media_list,
        ["groups"] = t.groups,
        ["attributes"] = t.attributes,
        ["prices"] = t.prices,
        ["vc_prices"] = t.vc_prices,
        ["is_enabled"] = t.is_enabled,
        ["is_deleted"] = t.is_deleted,
        ["is_show_in_store"] = t.is_show_in_store,
        ["is_free"] = t.is_free,
        ["is_hard"] = t.is_hard,
        ["order"] = t.order,
        ["pre_order"] = t.pre_order,
        ["regions"] = t.regions,
        ["limits"] = t.limits,
        ["periods"] = t.periods,
        ["custom_attributes"] = t.custom_attributes,
  })
end


function M.body_virtual_items_currency_admin_create_virtual_currency_package(t)
    assert(t.sku)
    assert(t.name)
    assert(t.description)
    assert(t.content)
    return json.encode({
        ["sku"] = t.sku,
        ["name"] = t.name,
        ["description"] = t.description,
        ["long_description"] = t.long_description,
        ["image_url"] = t.image_url,
        ["media_list"] = t.media_list,
        ["groups"] = t.groups,
        ["attributes"] = t.attributes,
        ["prices"] = t.prices,
        ["vc_prices"] = t.vc_prices,
        ["is_enabled"] = t.is_enabled,
        ["is_deleted"] = t.is_deleted,
        ["is_show_in_store"] = t.is_show_in_store,
        ["is_free"] = t.is_free,
        ["order"] = t.order,
        ["content"] = t.content,
        ["pre_order"] = t.pre_order,
        ["regions"] = t.regions,
        ["limits"] = t.limits,
        ["periods"] = t.periods,
        ["custom_attributes"] = t.custom_attributes,
  })
end


function M.body_create_update_region(t)
    assert(t.countries)
    assert(t.name)
    return json.encode({
        ["countries"] = t.countries,
        ["name"] = t.name,
  })
end


function M.body_reset_user_limits(t)
    assert(t.user)
    return json.encode({
        ["user"] = t.user,
  })
end


function M.body_reset_user_limits_flexible(t)
    assert(t.user)
    return json.encode({
        ["user"] = t.user,
  })
end


function M.body_update_user_limits_flexible(t)
    assert(t.user)
    assert(t.available)
    return json.encode({
        ["user"] = t.user,
        ["available"] = t.available,
  })
end


function M.body_update_user_limits_strict(t)
    assert(t.user)
    assert(t.available)
    return json.encode({
        ["user"] = t.user,
        ["available"] = t.available,
  })
end


function M.body_update_promo_code_user_limits_flexible(t)
    assert(t.user)
    assert(t.available)
    return json.encode({
        ["user"] = t.user,
        ["available"] = t.available,
  })
end


function M.body_update_promo_code_user_limits_strict(t)
    assert(t.user)
    assert(t.available)
    return json.encode({
        ["user"] = t.user,
        ["available"] = t.available,
  })
end


function M.body_update_coupon_user_limits_flexible(t)
    assert(t.user)
    assert(t.available)
    return json.encode({
        ["user"] = t.user,
        ["available"] = t.available,
  })
end


function M.body_update_coupon_user_limits_strict(t)
    assert(t.user)
    assert(t.available)
    return json.encode({
        ["user"] = t.user,
        ["available"] = t.available,
  })
end


function M.body_create_value_point(t)
    assert(t.sku)
    assert(t.name)
    return json.encode({
        ["description"] = t.description,
        ["image_url"] = t.image_url,
        ["is_enabled"] = t.is_enabled,
        ["long_description"] = t.long_description,
        ["media_list"] = t.media_list,
        ["name"] = t.name,
        ["order"] = t.order,
        ["sku"] = t.sku,
        ["is_clan"] = t.is_clan,
  })
end


function M.body_set_item_value_point_reward(t)
    return json.encode({
  })
end


function M.body_set_item_value_point_reward_for_patch(t)
    return json.encode({
  })
end


function M.body_create_reward_chain(t)
    return json.encode({
  })
end


function M.body_update_reward_chain(t)
    return json.encode({
  })
end


function M.body_promotions_unique_catalog_offer_create(t)
    assert(t.external_id)
    assert(t.name)
    return json.encode({
        ["external_id"] = t.external_id,
        ["date_start"] = t.date_start,
        ["date_end"] = t.date_end,
        ["name"] = t.name,
        ["items"] = t.items,
        ["redeem_user_limit"] = t.redeem_user_limit,
        ["redeem_code_limit"] = t.redeem_code_limit,
        ["redeem_total_limit"] = t.redeem_total_limit,
  })
end


function M.body_promotions_unique_catalog_offer_update(t)
    assert(t.name)
    return json.encode({
        ["date_start"] = t.date_start,
        ["date_end"] = t.date_end,
        ["name"] = t.name,
        ["items"] = t.items,
        ["redeem_total_limit"] = t.redeem_total_limit,
        ["redeem_user_limit"] = t.redeem_user_limit,
        ["redeem_code_limit"] = t.redeem_code_limit,
  })
end


function M.body_connector_import_items_body(t)
    assert(t.connector_external_id)
    assert(t.file_url)
    return json.encode({
        ["connector_external_id"] = t.connector_external_id,
        ["file_url"] = t.file_url,
        ["mode"] = t.mode,
  })
end



--- Get list of attributes for administration
-- Gets the list of attributes from a project for administration.
-- /v2/project/{project_id}/admin/attribute
-- @name admin_get_attribute_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_attribute_list(project_id, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/attribute"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create attribute
-- Creates an attribute.
-- /v2/project/{project_id}/admin/attribute
-- @name admin_create_attribute
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_attribute(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/attribute"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update attribute
-- Updates an attribute.
-- /v2/project/{project_id}/admin/attribute/{external_id}
-- @name admin_update_attribute
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Attribute external ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_attribute(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/attribute/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get specified attribute
-- Gets a specified attribute.
-- /v2/project/{project_id}/admin/attribute/{external_id}
-- @name admin_get_attribute
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Attribute external ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_attribute(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/attribute/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete attribute
-- Deletes an attribute.
-- /v2/project/{project_id}/admin/attribute/{external_id}
-- @name delete_attribute
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Attribute external ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.delete_attribute(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/attribute/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create attribute value
-- Creates an attribute value.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of attribute values. The default and maximum value is 20 values per attribute.
-- /v2/project/{project_id}/admin/attribute/{external_id}/value
-- @name admin_create_attribute_value
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Attribute external ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_attribute_value(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/attribute/{external_id}/value"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete all values of attribute
-- Deletes all values of the attribute.
-- /v2/project/{project_id}/admin/attribute/{external_id}/value
-- @name admin_delete_all_attribute_value
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Attribute external ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_all_attribute_value(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/attribute/{external_id}/value"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update attribute value
-- Updates an attribute values.
-- /v2/project/{project_id}/admin/attribute/{external_id}/value/{value_external_id}
-- @name admin_update_attribute_value
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param value_external_id (REQUIRED) Attribute value external ID.
-- @param external_id (REQUIRED) Attribute external ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_attribute_value(project_id, value_external_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(value_external_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/attribute/{external_id}/value/{value_external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{value_external_id}", uri.encode(value_external_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete attribute value
-- Deletes an attribute value.
-- /v2/project/{project_id}/admin/attribute/{external_id}/value/{value_external_id}
-- @name admin_delete_attribute_value
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param value_external_id (REQUIRED) Attribute value external ID.
-- @param external_id (REQUIRED) Attribute external ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_attribute_value(project_id, value_external_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(value_external_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/attribute/{external_id}/value/{value_external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{value_external_id}", uri.encode(value_external_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of catalog filter rules
-- Gets all rules applying to user attributes.
-- /v2/project/{project_id}/admin/user/attribute/rule
-- @name get_filter_rules
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param is_enabled Filter elements by `is_enabled` flag.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_filter_rules(project_id, limit, offset, is_enabled, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/user/attribute/rule"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["is_enabled"] = is_enabled

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create catalog filter rule
-- Create rule for user attributes.
-- /v2/project/{project_id}/admin/user/attribute/rule
-- @name create_filter_rule
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_filter_rule(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/user/attribute/rule"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get all catalog rules for searching on client-side
-- Gets a list of all catalog rules for searching on the client-side.
-- Attention
-- 
-- Returns only rule id, name and is_enabled
-- /v2/project/{project_id}/admin/user/attribute/rule/all
-- @name get_all_filter_rules
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_all_filter_rules(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/user/attribute/rule/all"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get catalog filter rule
-- Get specific rule applying to user attributes.
-- /v2/project/{project_id}/admin/user/attribute/rule/{rule_id}
-- @name get_filter_rule_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param rule_id (REQUIRED) Rule ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_filter_rule_by_id(project_id, rule_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(rule_id)

    local url_path = "/v2/project/{project_id}/admin/user/attribute/rule/{rule_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{rule_id}", uri.encode(rule_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update catalog filter rule
-- Updates a specific rule applying to user attributes. The default value will be used for a not specified property (if property is not required).
-- /v2/project/{project_id}/admin/user/attribute/rule/{rule_id}
-- @name update_filter_rule_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param rule_id (REQUIRED) Rule ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_filter_rule_by_id(project_id, rule_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(rule_id)

    local url_path = "/v2/project/{project_id}/admin/user/attribute/rule/{rule_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{rule_id}", uri.encode(rule_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Patch catalog filter rule
-- Updates a specific rule applying to user attributes. The current value will be used for a not specified property.
-- /v2/project/{project_id}/admin/user/attribute/rule/{rule_id}
-- @name patch_filter_rule_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param rule_id (REQUIRED) Rule ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.patch_filter_rule_by_id(project_id, rule_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(rule_id)

    local url_path = "/v2/project/{project_id}/admin/user/attribute/rule/{rule_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{rule_id}", uri.encode(rule_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PATCH", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete catalog filter rule
-- Deletes a specific rule.
-- /v2/project/{project_id}/admin/user/attribute/rule/{rule_id}
-- @name delete_filter_rule_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param rule_id (REQUIRED) Rule ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.delete_filter_rule_by_id(project_id, rule_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(rule_id)

    local url_path = "/v2/project/{project_id}/admin/user/attribute/rule/{rule_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{rule_id}", uri.encode(rule_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of bundles for administration
-- Gets the list of bundles within a project for administration.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/bundle
-- @name admin_get_bundle_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_bundle_list(project_id, limit, offset, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/bundle"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create bundle
-- Creates a bundle.
-- /v2/project/{project_id}/admin/items/bundle
-- @name admin_create_bundle
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_bundle(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/bundle"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of bundles by specified group id
-- Gets the list of bundles within a group for administration.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/bundle/group/id/{group_id}
-- @name admin_get_bundle_list_in_group_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param group_id (REQUIRED) Group ID.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_bundle_list_in_group_by_id(project_id, group_id, limit, offset, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(group_id)

    local url_path = "/v2/project/{project_id}/admin/items/bundle/group/id/{group_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{group_id}", uri.encode(group_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of bundles by specified group external id
-- Gets the list of bundles within a group for administration.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/bundle/group/external_id/{external_id}
-- @name admin_get_bundle_list_in_group_by_external_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Group external ID.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_bundle_list_in_group_by_external_id(project_id, external_id, limit, offset, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/items/bundle/group/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update bundle
-- Updates a bundle.
-- /v2/project/{project_id}/admin/items/bundle/sku/{sku}
-- @name admin_update_bundle
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param sku (REQUIRED) Bundle SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_bundle(project_id, sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(sku)

    local url_path = "/v2/project/{project_id}/admin/items/bundle/sku/{sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{sku}", uri.encode(sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete bundle
-- Deletes a bundle.
-- /v2/project/{project_id}/admin/items/bundle/sku/{sku}
-- @name admin_delete_bundle
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param sku (REQUIRED) Bundle SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_bundle(project_id, sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(sku)

    local url_path = "/v2/project/{project_id}/admin/items/bundle/sku/{sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{sku}", uri.encode(sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get bundle
-- Gets the bundle within a project for administration.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/bundle/sku/{sku}
-- @name admin_get_bundle
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param sku (REQUIRED) Bundle SKU.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_bundle(project_id, sku, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(sku)

    local url_path = "/v2/project/{project_id}/admin/items/bundle/sku/{sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{sku}", uri.encode(sku))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Show bundle in catalog
-- Shows a bundle in a catalog.
-- /v2/project/{project_id}/admin/items/bundle/sku/{sku}/show
-- @name admin_show_bundle
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param sku (REQUIRED) Bundle SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_show_bundle(project_id, sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(sku)

    local url_path = "/v2/project/{project_id}/admin/items/bundle/sku/{sku}/show"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{sku}", uri.encode(sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Hide bundle in catalog
-- Hides a bundle in a catalog.
-- /v2/project/{project_id}/admin/items/bundle/sku/{sku}/hide
-- @name admin_hide_bundle
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param sku (REQUIRED) Bundle SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_hide_bundle(project_id, sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(sku)

    local url_path = "/v2/project/{project_id}/admin/items/bundle/sku/{sku}/hide"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{sku}", uri.encode(sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of bundles
-- Gets a list of bundles for building a catalog.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. 
--  Note
-- 
-- In general, the use of catalog of items is available without authorization.
--  Only authorized users can get a personalized catalog.
-- /v2/project/{project_id}/items/bundle
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
function M.get_bundle_list(project_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/bundle"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get specified bundle
-- Gets a specified bundle.
-- 
-- Note
-- 
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- /v2/project/{project_id}/items/bundle/sku/{sku}
-- @name get_bundle
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param sku (REQUIRED) Bundle SKU.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_bundle(project_id, sku, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(sku)

    local url_path = "/v2/project/{project_id}/items/bundle/sku/{sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{sku}", uri.encode(sku))

    local query_params = {}
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of bundles by specified group
-- Gets a list of bundles within a group for building a catalog.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. 
--  Note
-- 
-- In general, the use of catalog of items is available without authorization.
--  Only authorized users can get a personalized catalog.
-- /v2/project/{project_id}/items/bundle/group/{external_id}
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
function M.get_bundle_list_in_group(project_id, external_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/items/bundle/group/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get cart by cart ID
-- Returns user’s cart by cart ID.
-- /v2/project/{project_id}/cart/{cart_id}
-- @name get_cart_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param currency The item price currency displayed in the cart. Three-letter currency code per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). Check the documentation for detailed information about [currencies supported by Xsolla](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_cart_by_id(project_id, cart_id, currency, locale, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/project/{project_id}/cart/{cart_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{cart_id}", uri.encode(cart_id))

    local query_params = {}
    query_params["currency"] = currency
    query_params["locale"] = locale

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get current user&#x27;s cart
-- Returns the current user&amp;#x27;s cart.
-- /v2/project/{project_id}/cart
-- @name get_user_cart
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param currency The item price currency displayed in the cart. Three-letter currency code per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). Check the documentation for detailed information about [currencies supported by Xsolla](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/).
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_user_cart(project_id, currency, locale, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/cart"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["currency"] = currency
    query_params["locale"] = locale

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete all cart items by cart ID
-- Deletes all cart items.
-- /v2/project/{project_id}/cart/{cart_id}/clear
-- @name cart_clear_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.cart_clear_by_id(project_id, cart_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/project/{project_id}/cart/{cart_id}/clear"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{cart_id}", uri.encode(cart_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete all cart items from current cart
-- Deletes all cart items.
-- /v2/project/{project_id}/cart/clear
-- @name cart_clear
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.cart_clear(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/cart/clear"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Fill cart with items
-- Fills the cart with items. If the cart already has an item with the same SKU, the existing item will be replaced by the passed value.
-- /v2/project/{project_id}/cart/fill
-- @name cart_fill
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.cart_fill(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/cart/fill"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Fill specific cart with items
-- Fills the specific cart with items. If the cart already has an item with the same SKU, the existing item position will be replaced by the passed value.
-- /v2/project/{project_id}/cart/{cart_id}/fill
-- @name cart_fill_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.cart_fill_by_id(project_id, cart_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/project/{project_id}/cart/{cart_id}/fill"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{cart_id}", uri.encode(cart_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update cart item by cart ID
-- Updates an existing cart item or creates the one in the cart.
-- /v2/project/{project_id}/cart/{cart_id}/item/{item_sku}
-- @name put_item_by_cart_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.put_item_by_cart_id(project_id, cart_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(cart_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/cart/{cart_id}/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{cart_id}", uri.encode(cart_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete cart item by cart ID
-- Removes an item from the cart.
-- /v2/project/{project_id}/cart/{cart_id}/item/{item_sku}
-- @name delete_item_by_cart_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.delete_item_by_cart_id(project_id, cart_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(cart_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/cart/{cart_id}/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{cart_id}", uri.encode(cart_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update cart item from current cart
-- Updates an existing cart item or creates the one in the cart.
-- /v2/project/{project_id}/cart/item/{item_sku}
-- @name put_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.put_item(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/cart/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete cart item from current cart
-- Removes an item from the cart.
-- /v2/project/{project_id}/cart/item/{item_sku}
-- @name delete_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.delete_item(project_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/cart/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
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
-- 
--  As this method uses the IP to determine the user’s country and select a currency for the order, it is important to only use this method from the client side and not from the server side. Using this method from the server side may cause incorrect currency determination and affect payment methods in Pay Station. 
-- /v2/project/{project_id}/payment/cart/{cart_id}
-- @name create_order_by_cart_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_order_by_cart_id(project_id, cart_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/project/{project_id}/payment/cart/{cart_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{cart_id}", uri.encode(cart_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
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
-- 
--  As this method uses the IP to determine the user’s country and select a currency for the order, it is important to only use this method from the client side and not from the server side. Using this method from the server side may cause incorrect currency determination and affect payment methods in Pay Station. 
-- /v2/project/{project_id}/payment/cart
-- @name create_order
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_order(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/payment/cart"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
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
-- 
--  As this method uses the IP to determine the user’s country and select a currency for the order, it is important to only use this method from the client side and not from the server side. Using this method from the server side may cause incorrect currency determination and affect payment methods in Pay Station. 
-- /v2/project/{project_id}/payment/item/{item_sku}
-- @name create_order_with_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_order_with_item(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/payment/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create order with free cart
-- Creates an order with all items from the free cart. The created order will get a `done` order status.
-- /v2/project/{project_id}/free/cart
-- @name create_free_order
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_free_order(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/free/cart"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create order with particular free cart
-- Creates an order with all items from the particular free cart. The created order will get a `done` order status.
-- /v2/project/{project_id}/free/cart/{cart_id}
-- @name create_free_order_by_cart_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_free_order_by_cart_id(project_id, cart_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/project/{project_id}/free/cart/{cart_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{cart_id}", uri.encode(cart_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create order with specified free item
-- Creates an order with a specified free item. The created order will get a `done` order status.
-- /v2/project/{project_id}/free/item/{item_sku}
-- @name create_free_order_with_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_free_order_with_item(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/free/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get order
-- Retrieves a specified order.
-- /v2/project/{project_id}/order/{order_id}
-- @name get_order
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param order_id (REQUIRED) Order ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_order(project_id, order_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(order_id)

    local url_path = "/v2/project/{project_id}/order/{order_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{order_id}", uri.encode(order_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get orders list for specified period
-- Retrieves orders list, arranged from the earliest to the latest creation date.
-- /v3/project/{project_id}/admin/order/search
-- @name admin_order_search
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_order_search(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v3/project/{project_id}/admin/order/search"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create payment token for purchase
-- Generates an order and a payment token for it. The order is generated based on the items passed in the request body.
-- 
-- To open the payment UI in a new window, use the following link: `https://secure.xsolla.com/paystation4/?token={token}`, where `{token}` is the received token.
-- 
-- For testing purposes, use this URL: `https://sandbox-secure.xsolla.com/paystation4/?token={token}`.
-- 
-- Notice
--    
-- 
-- 
--    user.country.value parameter is used to select a currency for the order. If user&amp;#x27;s country is unknown,
-- providing the user&amp;#x27;s IP in X-User-Ip header is an alternative option. 
--  One of these two options is required for the correct work of this method. 
--  The selected currency is used for payment methods at Pay Station.
--    
-- /v3/project/{project_id}/admin/payment/token
-- @name admin_create_payment_token
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_payment_token(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v3/project/{project_id}/admin/payment/token"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Fill cart with items
-- Fills the current cart with items. If the cart already has an item with the same SKU, the existing item will be replaced by the passed value.
-- /v2/admin/project/{project_id}/cart/fill
-- @name admin_cart_fill
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param x_user_for User identifier can be transferred by using the Xsolla Login User JWT or the [Pay Station access token](https://developers.xsolla.com/pay-station-api/current/token/create-token).
-- @param x_user_id You can use your own user ID when selling a cart with games.

-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_cart_fill(project_id, locale, x_user_for, x_user_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/admin/project/{project_id}/cart/fill"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["locale"] = locale

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Fill cart by cart ID with items
-- Fills the cart by cart ID with items. If the cart already has an item with the same SKU, the existing item will be replaced by the passed value.
-- /v2/admin/project/{project_id}/cart/{cart_id}/fill
-- @name admin_fill_cart_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param x_user_for User identifier can be transferred by using the Xsolla Login User JWT or the [Pay Station access token](https://developers.xsolla.com/pay-station-api/current/token/create-token).
-- @param x_user_id You can use your own user ID when selling a cart with games.

-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_fill_cart_by_id(project_id, cart_id, locale, x_user_for, x_user_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/admin/project/{project_id}/cart/{cart_id}/fill"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{cart_id}", uri.encode(cart_id))

    local query_params = {}
    query_params["locale"] = locale

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get information about webhook settings
-- Gets the information about the webhook settings in Store.
-- Check webhooks [documentation](https://developers.xsolla.com/doc/in-game-store/integration-guide/set-up-webhooks/) to learn more.
-- /v2/project/{project_id}/admin/webhook
-- @name get_webhook
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_webhook(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/webhook"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update information about webhook settings
-- Updates the information about the webhook settings in Store.
-- Check webhooks [documentation](/doc/in-game-store/integration-guide/set-up-webhooks/) to learn more.
-- /v2/project/{project_id}/admin/webhook
-- @name update_webhook
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_webhook(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/webhook"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get information about item pre-order limit
-- Get pre-order limit of the item.
-- 
-- Pre-Order limit API allows you to sell an item in a limited quantity. For configuring the pre-order itself, go to the Admin section of the desired item module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp;amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/pre_order/limit/item/id/{item_id}
-- /v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}
-- @name get_pre_order_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_pre_order_limit(project_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Add quantity to item pre-order limit
-- Add quantity to pre-order limit of the item.
-- 
-- Pre-Order limit API allows you to sell an item in a limited quantity. For configuring the pre-order itself, go to the Admin section of the desired item module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp;amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/pre_order/limit/item/id/{item_id}
-- /v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}
-- @name add_pre_order_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.add_pre_order_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Set quantity of item pre-order limit
-- Set quantity of pre-order limit of the item.
-- 
-- Pre-Order limit API allows you to sell an item in a limited quantity. For configuring the pre-order itself, go to the Admin section of the desired item module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp;amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/pre_order/limit/item/id/{item_id}
-- /v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}
-- @name set_pre_order_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.set_pre_order_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Remove quantity of item pre-order limit
-- Remove quantity of pre-order limit of the item.
-- 
-- Pre-Order limit API allows you to sell an item in a limited quantity. For configuring the pre-order itself, go to the Admin section of the desired item module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp;amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/pre_order/limit/item/id/{item_id}
-- /v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}
-- @name remove_pre_order_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.remove_pre_order_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Toggle item&#x27;s pre-order limit
-- Enable/disable pre-order limit of the item.
-- 
-- Pre-Order limit API allows you to sell an item in a limited quantity. For configuring the pre-order itself, go to the admin section of the desired item module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp;amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/pre_order/limit/item/id/{item_id}/toggle
-- /v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}/toggle
-- @name toggle_pre_order_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.toggle_pre_order_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}/toggle"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Remove all quantity of item pre-order limit
-- Remove all quantity of pre-order limit of the item.
-- 
-- Pre-Order limit API allows you to sell an item in a limited quantity. For configuring the pre-order itself, go to the admin section of the desired item module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp;amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/pre_order/limit/item/id/{item_id}/all
-- /v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}/all
-- @name remove_all_pre_order_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.remove_all_pre_order_limit(project_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}/all"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get information about upsell in project
-- Retrieves the information about upsell in project: whether it&amp;#x27;s enabled, type of upsell, and the SKU list of items that are a part of this upsell.
-- /v2/project/{project_id}/admin/items/upsell
-- @name get_upsell_configurations_for_project_admin
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_upsell_configurations_for_project_admin(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/upsell"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create upsell
-- Creates an upsell for a project.
-- /v2/project/{project_id}/admin/items/upsell
-- @name post_upsell
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.post_upsell(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/upsell"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update upsell
-- Update an upsell for a project.
-- /v2/project/{project_id}/admin/items/upsell
-- @name put_upsell
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.put_upsell(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/upsell"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Activate/Deactivate project&#x27;s upsell
-- Changes an upsell’s status in a project to be either active or inactive.
-- /v2/project/{project_id}/admin/items/upsell/{toggle}
-- @name put_upsell_toggle_active_inactive
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param toggle (REQUIRED) Activation status.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.put_upsell_toggle_active_inactive(project_id, toggle, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(toggle)

    local url_path = "/v2/project/{project_id}/admin/items/upsell/{toggle}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{toggle}", uri.encode(toggle))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of upsell items in project
-- Gets a list of upsell items in a project if they have already been set up.
-- /v2/project/{project_id}/items/upsell
-- @name get_upsell_for_project_client
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_upsell_for_project_client(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/upsell"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get projects
-- Gets the list of merchant&amp;#x27;s projects.
-- 
-- 
--   NoticeThis API call does not contain the project_id path parameter, so you need to use the API key that is valid in all the company’s projects to set up authorization.
-- 
-- /v2/merchant/{merchant_id}/projects
-- @name get_projects
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param merchant_id (REQUIRED) Merchant ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_projects(limit, offset, merchant_id, callback, retry_policy, cancellation_token)
    assert(merchant_id)

    local url_path = "/v2/merchant/{merchant_id}/projects"
    url_path = url_path:gsub("{merchant_id}", uri.encode(merchant_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get games list
-- Gets a games list for building a catalog.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
--  Note
-- 
-- In general, the use of catalog of items is available without authorization.
--  Only authorized users can get a personalized catalog.
-- /v2/project/{project_id}/items/game
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
function M.get_games_list(project_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/game"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get games list by specified group
-- Gets a games list from the specified group for building a catalog.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
--  Note
-- 
-- In general, the use of catalog of items is available without authorization.
--  Only authorized users can get a personalized catalog.
-- /v2/project/{project_id}/items/game/group/{external_id}
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
function M.get_games_group(project_id, external_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/items/game/group/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get game for catalog
-- Gets a game for the catalog.
-- 
-- Note
-- 
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- /v2/project/{project_id}/items/game/sku/{item_sku}
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
function M.get_game_by_sku(project_id, item_sku, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/items/game/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get game key for catalog
-- Gets a game key for the catalog.
-- 
-- Note
-- 
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- /v2/project/{project_id}/items/game/key/sku/{item_sku}
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
function M.get_game_key_by_sku(project_id, item_sku, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/items/game/key/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get game keys list by specified group
-- Gets a game key list from the specified group for building a catalog.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
--  Note
-- 
-- In general, the use of catalog of items is available without authorization.
--  Only authorized users can get a personalized catalog.
-- /v2/project/{project_id}/items/game/key/group/{external_id}
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
function M.get_game_keys_group(project_id, external_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/items/game/key/group/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get DRM list
-- Gets the list of available DRMs.
-- /v2/project/{project_id}/items/game/drm
-- @name get_drm_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_drm_list(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/game/drm"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create game
-- Creates a game in the project.
-- /v2/project/{project_id}/admin/items/game
-- @name admin_create_game
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_game(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/game"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of games for administration
-- Gets the list of games within a project for administration.
-- Game consists of game keys which could be purchased by a user.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/game
-- @name admin_get_game_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_game_list(project_id, limit, offset, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/game"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get game for administration
-- Gets a game for administration.
-- Game consists of game keys which could be purchased by a user.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/game/sku/{item_sku}
-- @name admin_get_game_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_game_by_sku(project_id, item_sku, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/game/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update game by SKU
-- Updates a game in the project by SKU.
-- /v2/project/{project_id}/admin/items/game/sku/{item_sku}
-- @name admin_update_game_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_game_by_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/game/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete game by SKU
-- Deletes a game in the project by SKU.
-- /v2/project/{project_id}/admin/items/game/sku/{item_sku}
-- @name admin_delete_game_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_game_by_sku(project_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/game/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get game for administration by ID
-- Gets a game for administration.
-- Game consists of game keys which could be purchased by a user.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/game/id/{item_id}
-- @name admin_get_game_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_game_by_id(project_id, item_id, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/admin/items/game/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_id}", uri.encode(item_id))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update game by ID
-- Updates a game in the project by ID.
-- /v2/project/{project_id}/admin/items/game/id/{item_id}
-- @name admin_update_game_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_game_by_id(project_id, item_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/admin/items/game/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_id}", uri.encode(item_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete game by ID
-- Deletes a game in the project by ID.
-- /v2/project/{project_id}/admin/items/game/id/{item_id}
-- @name admin_delete_game_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_game_by_id(project_id, item_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/admin/items/game/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_id}", uri.encode(item_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Upload codes
-- Uploads codes by game key SKU.
-- /v2/project/{project_id}/admin/items/game/key/upload/sku/{item_sku}
-- @name admin_upload_codes_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_upload_codes_by_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/game/key/upload/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Upload codes by ID
-- Uploads codes by game key ID.
-- /v2/project/{project_id}/admin/items/game/key/upload/id/{item_id}
-- @name admin_upload_codes_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_upload_codes_by_id(project_id, item_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/admin/items/game/key/upload/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_id}", uri.encode(item_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get codes loading session information
-- Gets codes loading session information.
-- /v2/project/{project_id}/admin/items/game/key/upload/session/{session_id}
-- @name admin_get_codes_session
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param session_id (REQUIRED) Session ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_codes_session(project_id, session_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(session_id)

    local url_path = "/v2/project/{project_id}/admin/items/game/key/upload/session/{session_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{session_id}", uri.encode(session_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get codes
-- Gets a certain number of codes by game key SKU.
-- /v2/project/{project_id}/admin/items/game/key/request/sku/{item_sku}
-- @name admin_get_codes_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param user_email (REQUIRED) User email.
-- @param quantity (REQUIRED) Codes quantity.
-- @param reason (REQUIRED) Reason receiving codes.
-- @param region_id Region ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_codes_by_sku(project_id, item_sku, user_email, quantity, reason, region_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)
    assert(user_email)
    assert(quantity)
    assert(reason)

    local url_path = "/v2/project/{project_id}/admin/items/game/key/request/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}
    query_params["user_email"] = user_email
    query_params["quantity"] = quantity
    query_params["reason"] = reason
    query_params["region_id"] = region_id

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get codes by ID
-- Gets a certain number of codes by game key ID.
-- /v2/project/{project_id}/admin/items/game/key/request/id/{item_id}
-- @name admin_get_codes_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param user_email (REQUIRED) User email.
-- @param quantity (REQUIRED) Codes quantity.
-- @param reason (REQUIRED) Reason receiving codes.
-- @param region_id Region ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_codes_by_id(project_id, item_id, user_email, quantity, reason, region_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_id)
    assert(user_email)
    assert(quantity)
    assert(reason)

    local url_path = "/v2/project/{project_id}/admin/items/game/key/request/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_id}", uri.encode(item_id))

    local query_params = {}
    query_params["user_email"] = user_email
    query_params["quantity"] = quantity
    query_params["reason"] = reason
    query_params["region_id"] = region_id

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete codes
-- Deletes all codes by game key SKU.
-- /v2/project/{project_id}/admin/items/game/key/delete/sku/{item_sku}
-- @name admin_delete_codes_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param user_email (REQUIRED) User email.
-- @param reason (REQUIRED) Reason receiving codes.
-- @param region_id Region ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_codes_by_sku(project_id, item_sku, user_email, reason, region_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)
    assert(user_email)
    assert(reason)

    local url_path = "/v2/project/{project_id}/admin/items/game/key/delete/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}
    query_params["user_email"] = user_email
    query_params["reason"] = reason
    query_params["region_id"] = region_id

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete codes by ID
-- Deletes all codes by game key ID.
-- /v2/project/{project_id}/admin/items/game/key/delete/id/{item_id}
-- @name admin_delete_codes_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param user_email (REQUIRED) User email.
-- @param reason (REQUIRED) Reason receiving codes.
-- @param region_id Region ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_codes_by_id(project_id, item_id, user_email, reason, region_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_id)
    assert(user_email)
    assert(reason)

    local url_path = "/v2/project/{project_id}/admin/items/game/key/delete/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_id}", uri.encode(item_id))

    local query_params = {}
    query_params["user_email"] = user_email
    query_params["reason"] = reason
    query_params["region_id"] = region_id

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of games owned by user
-- Get the list of games owned by the user. The response will contain an array of games owned by a particular user.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields.
-- /v2/project/{project_id}/entitlement
-- @name get_user_games
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param sandbox What type of entitlements should be returned. If the parameter is set to 1, the entitlements received by the user in the sandbox mode only are returned. If the parameter isn&#x27;t passed or is set to 0, the entitlements received by the user in the live mode only are returned.
-- @param additional_fields The list of additional fields. These fields will be in the response if you send them in your request. Available fields `attributes`.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_user_games(project_id, limit, offset, sandbox, additional_fields, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/entitlement"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["sandbox"] = sandbox
    query_params["additional_fields"] = additional_fields

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Redeem game code by client
-- Grants entitlement by a provided game code.
-- 
-- Attention
-- 
-- You can redeem codes only for the DRM-free platform.
-- /v2/project/{project_id}/entitlement/redeem
-- @name redeem_game_pin_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.redeem_game_pin_code(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/entitlement/redeem"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Grant entitlement (admin)
-- Grants entitlement to user.
-- 
-- Attention
-- 
-- Game codes or games for DRM free platform can be granted only.
-- /v2/project/{project_id}/admin/entitlement/grant
-- @name grant_entitlement_admin
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.grant_entitlement_admin(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/entitlement/grant"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Revoke entitlement (admin)
-- Revokes entitlement of user.
-- 
-- Attention
-- 
-- Game codes or games for DRM free platform can be revoked only.
-- /v2/project/{project_id}/admin/entitlement/revoke
-- @name revoke_entitlement_admin
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.revoke_entitlement_admin(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/entitlement/revoke"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get physical items list
-- Gets a physical items list for building a catalog.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
--  Note
-- 
-- In general, the use of catalog of items is available without authorization.
--  Only authorized users can get a personalized catalog.
-- /v2/project/{project_id}/items/physical_good
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
function M.get_physical_goods_list(project_id, limit, offset, locale, additional_fields, country, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/physical_good"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create physical item
-- Adds a new item.
-- /v2/project/{project_id}/admin/items/physical_good
-- @name admin_create_physical_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_physical_item(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of physical goods for administration
-- Gets the list of physical goods within a project for administration.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/physical_good
-- @name admin_get_physical_item_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_physical_item_list(project_id, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get physical item
-- Gets a physical item.
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/physical_good/id/{item_id}
-- /v2/project/{project_id}/admin/items/physical_good/sku/{item_sku}
-- @name admin_get_physical_item_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_physical_item_by_sku(project_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update physical item
-- Updates a physical item.
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/physical_good/id/{item_id}
-- /v2/project/{project_id}/admin/items/physical_good/sku/{item_sku}
-- @name admin_update_physical_item_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_physical_item_by_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Partially update physical item
-- Partially updates a physical item.
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/physical_good/id/{item_id}
-- /v2/project/{project_id}/admin/items/physical_good/sku/{item_sku}
-- @name admin_patch_physical_item_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_patch_physical_item_by_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PATCH", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete physical item
-- Deletes a physical item.
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/physical_good/id/{item_id}
-- /v2/project/{project_id}/admin/items/physical_good/sku/{item_sku}
-- @name delete_physical_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.delete_physical_item(project_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get physical item by ID
-- Gets a physical item by ID.
-- /v2/project/{project_id}/admin/items/physical_good/id/{item_id}
-- @name admin_get_physical_item_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_physical_item_by_id(project_id, item_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_id}", uri.encode(item_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update physical item by ID
-- Updates a physical item by ID.
-- /v2/project/{project_id}/admin/items/physical_good/id/{item_id}
-- @name admin_update_physical_item_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_physical_item_by_id(project_id, item_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_id}", uri.encode(item_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Partially update physical item by ID
-- Partially updates a physical item by ID.
-- /v2/project/{project_id}/admin/items/physical_good/id/{item_id}
-- @name admin_patch_physical_item_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_patch_physical_item_by_id(project_id, item_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_id}", uri.encode(item_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PATCH", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete physical item by ID
-- Deletes a physical item by ID.
-- /v2/project/{project_id}/admin/items/physical_good/id/{item_id}
-- @name delete_physical_item_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.delete_physical_item_by_id(project_id, item_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_id}", uri.encode(item_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get all delivery methods
-- This API allows to specify method of item&amp;#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&amp;#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
-- 
-- 
-- To use the methods, you should specify fulfilment XSOLLA_SIMPLE in project
-- delivery settings.
-- /v2/project/{project_id}/admin/items/physical_good/delivery/method
-- @name admin_get_delivery_method
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_delivery_method(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/method"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Add new delivery method
-- This API allows to specify method of item&amp;#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&amp;#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
-- 
-- 
-- To use the methods, you should specify fulfilment XSOLLA_SIMPLE in project
-- delivery settings.
-- /v2/project/{project_id}/admin/items/physical_good/delivery/method
-- @name admin_create_delivery_method
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_delivery_method(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/method"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get delivery method information by method code
-- This API allows to specify method of item&amp;#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&amp;#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
-- 
-- 
-- To use the methods, you should specify fulfilment XSOLLA_SIMPLE in project
-- delivery settings.
-- 
-- Aliases for this endpoint:
-- 
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/method/id/{id}
-- /v2/project/{project_id}/admin/items/physical_good/delivery/method/code/{code}
-- @name admin_get_delivery_method_method_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param code (REQUIRED) Delivery method code.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_delivery_method_method_code(project_id, code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(code)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/method/code/{code}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{code}", uri.encode(code))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update delivery method information by method code
-- This API allows to specify method of item&amp;#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&amp;#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
-- 
-- 
-- To use the methods, you should specify fulfilment XSOLLA_SIMPLE in project
-- delivery settings.
-- 
-- Aliases for this endpoint:
-- 
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/method/id/{id}
-- /v2/project/{project_id}/admin/items/physical_good/delivery/method/code/{code}
-- @name admin_update_delivery_method_method_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param code (REQUIRED) Delivery method code.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_delivery_method_method_code(project_id, code, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(code)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/method/code/{code}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{code}", uri.encode(code))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Remove delivery method by method code
-- This API allows to specify method of item&amp;#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&amp;#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
-- 
-- 
-- To use the methods, you should specify fulfilment XSOLLA_SIMPLE in project
-- delivery settings.
-- 
-- Aliases for this endpoint:
-- 
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/method/id/{id}
-- /v2/project/{project_id}/admin/items/physical_good/delivery/method/code/{code}
-- @name admin_delete_delivery_method_method_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param code (REQUIRED) Delivery method code.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_delivery_method_method_code(project_id, code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(code)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/method/code/{code}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{code}", uri.encode(code))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get item delivery prices information
-- This API allows to specify method of item&amp;#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&amp;#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
-- 
-- 
-- To use the methods, you should specify fulfilment XSOLLA_SIMPLE in project
-- delivery settings.
-- 
-- Aliases for this endpoint:
-- 
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/price/item/id/{item_id}
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/price/method/id/{id}
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/price/method/code/{code}
-- /v2/project/{project_id}/admin/items/physical_good/delivery/price/item/sku/{item_sku}
-- @name admin_get_delivery_method_price_item_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_delivery_method_price_item_sku(project_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/price/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Add new delivery prices
-- This API allows to specify method of item&amp;#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&amp;#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
-- 
-- 
-- To use the methods, you should specify fulfilment XSOLLA_SIMPLE in project
-- delivery settings.
-- 
-- Aliases for this endpoint:
-- 
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/price/item/id/{item_id}
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/price/method/id/{id}
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/price/method/code/{code}
-- /v2/project/{project_id}/admin/items/physical_good/delivery/price/item/sku/{item_sku}
-- @name admin_add_delivery_method_price_item_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_add_delivery_method_price_item_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/price/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Remove delivery prices
-- This API allows to specify method of item&amp;#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&amp;#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
-- 
-- 
-- To use the methods, you should specify fulfilment XSOLLA_SIMPLE in project
-- delivery settings.
-- 
-- Aliases for this endpoint:
-- 
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/price/item/id/{item_id}
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/price/method/id/{id}
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/price/method/code/{code}
-- /v2/project/{project_id}/admin/items/physical_good/delivery/price/item/sku/{item_sku}
-- @name admin_delete_delivery_method_price_item_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_delivery_method_price_item_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/price/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Replace delivery prices
-- This API allows to specify method of item&amp;#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&amp;#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
-- 
-- 
-- To use the methods, you should specify fulfilment XSOLLA_SIMPLE in project
-- delivery settings.
-- 
-- Aliases for this endpoint:
-- 
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/price/item/id/{item_id}
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/price/method/id/{id}
-- * /v2/project/{project_id}/admin/items/physical_good/delivery/price/method/code/{code}
-- /v2/project/{project_id}/admin/items/physical_good/delivery/price/item/sku/{item_sku}
-- @name admin_replace_delivery_method_price_item_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_replace_delivery_method_price_item_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/price/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get all promotion list
-- Gets the list of promotions of a project.
-- /v2/project/{project_id}/admin/promotion
-- @name get_promotion_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param enabled Filter elements by `is_enabled` flag.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_promotion_list(project_id, limit, offset, enabled, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/promotion"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["enabled"] = enabled

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Activate promotion
-- Activates a promotion.
-- /v2/project/{project_id}/admin/promotion/{promotion_id}/activate
-- @name activate_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promotion_id (REQUIRED) Promotion ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.activate_promotion(project_id, promotion_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/{promotion_id}/activate"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promotion_id}", uri.encode(promotion_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Deactivate promotion
-- Deactivates a promotion.
-- /v2/project/{project_id}/admin/promotion/{promotion_id}/deactivate
-- @name deactivate_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promotion_id (REQUIRED) Promotion ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.deactivate_promotion(project_id, promotion_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/{promotion_id}/deactivate"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promotion_id}", uri.encode(promotion_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get redeemable promotion by code
-- Gets the promotion by a promo code or coupon code.
-- /v2/project/{project_id}/admin/promotion/redeemable/code/{code}
-- @name get_redeemable_promotion_by_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param code (REQUIRED) Unique case-sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_redeemable_promotion_by_code(project_id, code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(code)

    local url_path = "/v2/project/{project_id}/admin/promotion/redeemable/code/{code}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{code}", uri.encode(code))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Redeem coupon code
-- Redeems a coupon code. The user gets a bonus after a coupon is redeemed.
-- /v2/project/{project_id}/coupon/redeem
-- @name redeem_coupon
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.redeem_coupon(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/coupon/redeem"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get coupon rewards
-- Gets coupons rewards by its code.
-- Can be used to allow users to choose one of many items as a bonus.
-- The usual case is choosing a DRM if the coupon contains a game as a bonus (`type=unit`).
-- /v2/project/{project_id}/coupon/code/{coupon_code}/rewards
-- @name get_coupon_rewards_by_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param coupon_code (REQUIRED) Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_coupon_rewards_by_code(project_id, coupon_code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(coupon_code)

    local url_path = "/v2/project/{project_id}/coupon/code/{coupon_code}/rewards"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{coupon_code}", uri.encode(coupon_code))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create coupon promotion
-- Creates a coupon promotion.
-- /v2/project/{project_id}/admin/coupon
-- @name admin_create_coupon
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_coupon(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/coupon"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of coupon promotions
-- Gets the list of coupon promotions of a project.
-- /v2/project/{project_id}/admin/coupon
-- @name get_coupons
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_coupons(project_id, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/coupon"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update coupon promotion
-- Updates a coupon promotion.
-- /v2/project/{project_id}/admin/coupon/{external_id}
-- @name update_coupon_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_coupon_promotion(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/coupon/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get coupon promotion
-- Gets a specified coupon promotion.
-- /v2/project/{project_id}/admin/coupon/{external_id}
-- @name get_coupon
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_coupon(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/coupon/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete coupon promotion
-- Deletes [coupon promotion](https://developers.xsolla.com/doc/in-game-store/features/coupons/). The deleted promotion:
-- * Disappears from the list of promotions set up in your project.
-- * Is no longer applied to the item catalog. User can’t get bonus items with this promotion.
-- 
-- After deletion, the promotion can’t be restored.
-- Coupon codes from the deleted promotion can be [added](https://developers.xsolla.com/api/igs/operation/create-coupon-code/) to existing promotions.
-- /v2/project/{project_id}/admin/coupon/{external_id}
-- @name delete_coupon_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.delete_coupon_promotion(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/coupon/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Activate coupon promotion
-- Activates a coupon promotion.
-- Created coupon promotion is disabled by default.
-- It will not be ready for redemption until you activate it.
-- Use this endpoint to enable and activate a coupon promotion.
-- /v2/project/{project_id}/admin/coupon/{external_id}/activate
-- @name activate_coupon
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.activate_coupon(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/coupon/{external_id}/activate"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Deactivate coupon promotion
-- Deactivates a coupon promotion.
-- Created coupon promotion is disabled by default.
-- It will not be ready for redemption until you activate it.
-- Use this endpoint to disable and deactivate a coupon promotion.
-- /v2/project/{project_id}/admin/coupon/{external_id}/deactivate
-- @name deactivate_coupon
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.deactivate_coupon(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/coupon/{external_id}/deactivate"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create coupon code
-- Creates coupon code.
-- /v2/project/{project_id}/admin/coupon/{external_id}/code
-- @name create_coupon_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_coupon_code(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/coupon/{external_id}/code"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get coupon codes
-- Gets coupon codes.
-- /v2/project/{project_id}/admin/coupon/{external_id}/code
-- @name get_coupon_codes
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_coupon_codes(project_id, external_id, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/coupon/{external_id}/code"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Generate coupon codes
-- Generates coupon codes.
-- /v2/project/{project_id}/admin/coupon/{external_id}/code/generate
-- @name generate_coupon_codes
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.generate_coupon_codes(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/coupon/{external_id}/code/generate"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Redeem promo code
-- Redeems a code of promo code promotion.
-- After redeeming a promo code, the user will get free items and/or the price of the cart and/or particular items will be decreased.
-- /v2/project/{project_id}/promocode/redeem
-- @name redeem_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.redeem_promo_code(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/promocode/redeem"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Remove promo code from cart
-- Removes a promo code from a cart.
-- After the promo code is removed, the total price of all items in the cart will be recalculated without bonuses and discounts provided by a promo code.
-- /v2/project/{project_id}/promocode/remove
-- @name remove_cart_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.remove_cart_promo_code(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/promocode/remove"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get promo code reward
-- Gets promo code rewards by its code.
-- Can be used to allow users to choose one of many items as a bonus.
-- The usual case is choosing a DRM if the promo code contains a game as a bonus (`type=unit`).
-- /v2/project/{project_id}/promocode/code/{promocode_code}/rewards
-- @name get_promo_code_rewards_by_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promocode_code (REQUIRED) Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_promo_code_rewards_by_code(project_id, promocode_code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(promocode_code)

    local url_path = "/v2/project/{project_id}/promocode/code/{promocode_code}/rewards"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promocode_code}", uri.encode(promocode_code))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create promo code promotion
-- Creates a promo code promotion.
-- /v2/project/{project_id}/admin/promocode
-- @name create_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_promo_code(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/promocode"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of promo code promotions
-- Gets the list of promo codes of a project.
-- /v2/project/{project_id}/admin/promocode
-- @name get_promo_codes
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_promo_codes(project_id, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/promocode"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update promo code promotion
-- Updates a promo code promotion.
-- /v2/project/{project_id}/admin/promocode/{external_id}
-- @name update_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_promo_code(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/promocode/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get promo code promotion
-- Gets a specified promo code promotion.
-- /v2/project/{project_id}/admin/promocode/{external_id}
-- @name get_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_promo_code(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/promocode/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete promo code promotion
-- Deletes [promo code promotion](https://developers.xsolla.com/doc/in-game-store/features/promo-codes/). The deleted promotion:
-- * Disappears from the list of promotions set up in your project.
-- * Is no longer applied to the item catalog and the cart. User can’t get bonus items or purchase items using this promotion.
-- 
-- After deletion, the promotion can’t be restored.
-- Promo codes from the deleted promotion can be [added](https://developers.xsolla.com/api/igs/operation/create-promo-code-code/) to existing promotions.
-- /v2/project/{project_id}/admin/promocode/{external_id}
-- @name delete_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.delete_promo_code(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/promocode/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Activate promo code promotion
-- Activates a promo code promotion.
-- 
-- Created promo code promotion is disabled by default.
-- It will not be ready for redemption until you activate it.
-- Use this endpoint to enable and activate a promo code promotion.
-- /v2/project/{project_id}/admin/promocode/{external_id}/activate
-- @name activate_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.activate_promo_code(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/promocode/{external_id}/activate"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Deactivate promo code promotion
-- Deactivates a promo code promotion.
-- 
-- Created promo code promotion is disabled by default.
-- It will not be ready for redemption until you activate it.
-- Use this endpoint to disable and deactivate a promo code promotion.
-- /v2/project/{project_id}/admin/promocode/{external_id}/deactivate
-- @name deactivate_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.deactivate_promo_code(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/promocode/{external_id}/deactivate"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create code for promo code promotion
-- Creates code for a promo code promotion.
-- /v2/project/{project_id}/admin/promocode/{external_id}/code
-- @name create_promo_code_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_promo_code_code(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/promocode/{external_id}/code"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get codes of promo code promotion
-- Gets codes of a promo code promotion.
-- /v2/project/{project_id}/admin/promocode/{external_id}/code
-- @name get_promocode_codes
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_promocode_codes(project_id, external_id, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/promocode/{external_id}/code"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Generate codes for promo code promotion
-- Generates codes for a promo code promotion.
-- /v2/project/{project_id}/admin/promocode/{external_id}/code/generate
-- @name generate_promo_code_codes
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.generate_promo_code_codes(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/promocode/{external_id}/code/generate"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create discount promotion for item
-- Creates a discount promotion for an item.
-- 
-- Promotions provide a discount (%) on items.
-- The discount will be applied to all prices of the specified items.
-- /v2/project/{project_id}/admin/promotion/item
-- @name create_item_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_item_promotion(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/item"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of item promotions
-- Get the list of item promotions of a project.
-- 
-- Promotions provide a discount (%) on items.
-- The discount will be applied to all prices of the specified items.
-- /v2/project/{project_id}/admin/promotion/item
-- @name get_item_promotion_list
-- @param project_id (REQUIRED) Project ID.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_item_promotion_list(project_id, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/item"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update item promotion
-- Updates the promotion.
-- 
-- Note
-- 
-- New data will replace old data. If you want to update only a part of a promotion, you should transfer all required data in request as well.
-- 
-- Promotions provide a discount (%) on items.
-- The discount will be applied to all prices of the specified items.
-- /v2/project/{project_id}/admin/promotion/{promotion_id}/item
-- @name update_item_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promotion_id (REQUIRED) Promotion ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_item_promotion(project_id, promotion_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/{promotion_id}/item"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promotion_id}", uri.encode(promotion_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get item promotion
-- Gets the promotion applied to particular items.
-- 
-- Promotions provide a discount (%) on items.
-- The discount will be applied to all prices of the specified items.
-- /v2/project/{project_id}/admin/promotion/{promotion_id}/item
-- @name get_item_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promotion_id (REQUIRED) Promotion ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_item_promotion(project_id, promotion_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/{promotion_id}/item"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promotion_id}", uri.encode(promotion_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete item promotion
-- Deletes [discount promotion](https://developers.xsolla.com/doc/in-game-store/features/discounts/). The deleted promotion:
-- * Disappears from the list of promotions set up in your project.
-- * Is no longer applied to the item catalog and the cart. User can’t buy items with this promotion.
-- 
-- After deletion, the promotion can’t be restored.
-- /v2/project/{project_id}/admin/promotion/{promotion_id}/item
-- @name delete_item_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promotion_id (REQUIRED) Promotion ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.delete_item_promotion(project_id, promotion_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/{promotion_id}/item"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promotion_id}", uri.encode(promotion_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create bonus promotion
-- Creates the bonus promotion.
-- 
-- Promotion adds free bonus items to the purchase made by a user.
-- The promotion can be applied to every purchase within a project or to a purchase that includes particular items.
-- /v2/project/{project_id}/admin/promotion/bonus
-- @name create_bonus_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_bonus_promotion(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/bonus"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of bonus promotions
-- Gets the list of bonus promotions of a project.
-- 
-- Promotion adds free bonus items to the purchase made by a user.
-- The promotion can be applied to every purchase within a project or to a purchase that includes particular items.
-- /v2/project/{project_id}/admin/promotion/bonus
-- @name get_bonus_promotion_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_bonus_promotion_list(project_id, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/bonus"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update bonus promotion
-- Updates the promotion.
-- 
-- Note
-- 
-- New data will replace old data. If you want to update only a part of a promotion, you should transfer all required data in request as well.
-- 
-- Promotion adds free bonus items to the purchase made by a user.
-- The promotion can be applied to every purchase within a project or to a purchase that includes particular items.
-- /v2/project/{project_id}/admin/promotion/{promotion_id}/bonus
-- @name update_bonus_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promotion_id (REQUIRED) Promotion ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_bonus_promotion(project_id, promotion_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/{promotion_id}/bonus"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promotion_id}", uri.encode(promotion_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get bonus promotion
-- Gets the bonus promotion.
-- 
-- Promotion adds free bonus items to the purchase made by a user.
-- The promotion can be applied to every purchase within a project or to a purchase that includes particular items.
-- /v2/project/{project_id}/admin/promotion/{promotion_id}/bonus
-- @name get_bonus_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promotion_id (REQUIRED) Promotion ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_bonus_promotion(project_id, promotion_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/{promotion_id}/bonus"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promotion_id}", uri.encode(promotion_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete bonus promotion
-- Deletes [bonus promotion](https://developers.xsolla.com/doc/in-game-store/features/bonuses/). The deleted promotion:
-- * Disappears from the list of promotions set up in your project.
-- * Is no longer applied to the item catalog and the cart. User can’t get bonus items with this promotion.
-- 
-- After deletion, the promotion can’t be restored.
-- /v2/project/{project_id}/admin/promotion/{promotion_id}/bonus
-- @name delete_bonus_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promotion_id (REQUIRED) Promotion ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.delete_bonus_promotion(project_id, promotion_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/{promotion_id}/bonus"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promotion_id}", uri.encode(promotion_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Verify promotion code
-- Determines if the code is a promo code or coupon code and if the user can apply it.
-- /v2/project/{project_id}/promotion/code/{code}/verify
-- @name verify_promotion_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param code (REQUIRED) Unique case-sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.verify_promotion_code(project_id, code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(code)

    local url_path = "/v2/project/{project_id}/promotion/code/{code}/verify"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{code}", uri.encode(code))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of virtual items for administration
-- Gets the list of virtual items within a project for administration.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/virtual_items
-- @name admin_get_virtual_items_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_virtual_items_list(project_id, limit, offset, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_items"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create virtual item
-- Creates a virtual item.
-- /v2/project/{project_id}/admin/items/virtual_items
-- @name admin_create_virtual_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_virtual_item(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_items"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of virtual items by specified group external id
-- Gets the list of virtual items within a group for administration.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/virtual_items/group/external_id/{external_id}
-- @name admin_get_virtual_items_list_by_group_external_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Group external ID.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_virtual_items_list_by_group_external_id(project_id, external_id, limit, offset, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_items/group/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of virtual items by specified group id
-- Gets the list of virtual items within a group for administration.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/virtual_items/group/id/{group_id}
-- @name admin_get_virtual_items_list_by_group_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param group_id (REQUIRED) Group ID.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_virtual_items_list_by_group_id(project_id, group_id, limit, offset, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(group_id)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_items/group/id/{group_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{group_id}", uri.encode(group_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get virtual item
-- Gets the virtual item within a project for administration.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/virtual_items/sku/{item_sku}
-- @name admin_get_virtual_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_virtual_item(project_id, item_sku, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_items/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update virtual item
-- Updates a virtual item.
-- /v2/project/{project_id}/admin/items/virtual_items/sku/{item_sku}
-- @name admin_update_virtual_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_virtual_item(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_items/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete virtual item
-- Deletes a virtual item.
-- /v2/project/{project_id}/admin/items/virtual_items/sku/{item_sku}
-- @name admin_delete_virtual_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_virtual_item(project_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_items/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of virtual currencies for administration
-- Gets the list of virtual currencies within a project for administration.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/virtual_currency
-- @name admin_get_virtual_currencies_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_virtual_currencies_list(project_id, limit, offset, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create virtual currency
-- Creates a virtual currency.
-- /v2/project/{project_id}/admin/items/virtual_currency
-- @name admin_create_virtual_currency
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_virtual_currency(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get virtual currency
-- Gets the virtual currency within a project for administration.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/virtual_currency/sku/{virtual_currency_sku}
-- @name admin_get_virtual_currency
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param virtual_currency_sku (REQUIRED) Virtual currency SKU.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_virtual_currency(project_id, virtual_currency_sku, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(virtual_currency_sku)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency/sku/{virtual_currency_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{virtual_currency_sku}", uri.encode(virtual_currency_sku))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update virtual currency
-- Updates a virtual currency.
-- /v2/project/{project_id}/admin/items/virtual_currency/sku/{virtual_currency_sku}
-- @name admin_update_virtual_currency
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param virtual_currency_sku (REQUIRED) Virtual currency SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_virtual_currency(project_id, virtual_currency_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(virtual_currency_sku)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency/sku/{virtual_currency_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{virtual_currency_sku}", uri.encode(virtual_currency_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete virtual currency
-- Deletes a virtual currency.
-- /v2/project/{project_id}/admin/items/virtual_currency/sku/{virtual_currency_sku}
-- @name admin_delete_virtual_currency
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param virtual_currency_sku (REQUIRED) Virtual currency SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_virtual_currency(project_id, virtual_currency_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(virtual_currency_sku)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency/sku/{virtual_currency_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{virtual_currency_sku}", uri.encode(virtual_currency_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of virtual currency packages for administration
-- Gets the list of virtual currency packages within a project for administration.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/virtual_currency/package
-- @name admin_get_virtual_currency_packages_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_virtual_currency_packages_list(project_id, limit, offset, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency/package"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create virtual currency package
-- Creates a virtual currency package.
-- /v2/project/{project_id}/admin/items/virtual_currency/package
-- @name admin_create_virtual_currency_package
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_virtual_currency_package(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency/package"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update virtual currency package
-- Updates a virtual currency package.
-- /v2/project/{project_id}/admin/items/virtual_currency/package/sku/{item_sku}
-- @name admin_update_virtual_currency_package
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_virtual_currency_package(project_id, item_sku, promo_code, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency/package/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete virtual currency package
-- Deletes a virtual currency package.
-- /v2/project/{project_id}/admin/items/virtual_currency/package/sku/{item_sku}
-- @name admin_delete_virtual_currency_package
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_virtual_currency_package(project_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency/package/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get virtual currency package
-- Gets the virtual currency package within a project for administration.
-- 
-- Note
-- 
-- Do not use this endpoint for building a store catalog.
-- /v2/project/{project_id}/admin/items/virtual_currency/package/sku/{item_sku}
-- @name admin_get_virtual_currency_package
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_virtual_currency_package(project_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency/package/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get virtual items list
-- Gets a virtual items list for building a catalog.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
--  Note
-- 
-- In general, the use of catalog of items is available without authorization.
--  Only authorized users can get a personalized catalog.
-- /v2/project/{project_id}/items/virtual_items
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
function M.get_virtual_items(project_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/virtual_items"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get virtual item by SKU
-- Gets a virtual item by SKU for building a catalog.
-- Note
-- 
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- /v2/project/{project_id}/items/virtual_items/sku/{item_sku}
-- @name get_virtual_items_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_virtual_items_sku(project_id, item_sku, locale, country, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/items/virtual_items/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}
    query_params["locale"] = locale
    query_params["country"] = country
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get all virtual items list
-- Gets a list of all virtual items for searching on client-side.
-- 
-- Attention
-- 
-- Returns only item SKU, name, groups and description 
--  Note
-- 
-- In general, the use of catalog of items is available without authorization.
--  Only authorized users can get a personalized catalog.
-- /v2/project/{project_id}/items/virtual_items/all
-- @name get_all_virtual_items
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_all_virtual_items(project_id, locale, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/virtual_items/all"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["locale"] = locale
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get virtual currency list
-- Gets a virtual currency list for building a catalog.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
--  Note
-- 
-- In general, the use of catalog of items is available without authorization.
--  Only authorized users can get a personalized catalog.
-- /v2/project/{project_id}/items/virtual_currency
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
function M.get_virtual_currency(project_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/virtual_currency"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get virtual currency by SKU
-- Gets a virtual currency by SKU for building a catalog.
-- Note
-- 
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- /v2/project/{project_id}/items/virtual_currency/sku/{virtual_currency_sku}
-- @name get_virtual_currency_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param virtual_currency_sku (REQUIRED) Virtual currency SKU.
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_virtual_currency_sku(project_id, virtual_currency_sku, locale, country, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(virtual_currency_sku)

    local url_path = "/v2/project/{project_id}/items/virtual_currency/sku/{virtual_currency_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{virtual_currency_sku}", uri.encode(virtual_currency_sku))

    local query_params = {}
    query_params["locale"] = locale
    query_params["country"] = country
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get virtual currency package list
-- Gets a virtual currency packages list for building a catalog.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
--  Note
-- 
-- In general, the use of catalog of items is available without authorization.
--  Only authorized users can get a personalized catalog.
-- /v2/project/{project_id}/items/virtual_currency/package
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
function M.get_virtual_currency_package(project_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/virtual_currency/package"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get virtual currency package by SKU
-- Gets a virtual currency packages by SKU for building a catalog.
-- Note
-- 
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- /v2/project/{project_id}/items/virtual_currency/package/sku/{virtual_currency_package_sku}
-- @name get_virtual_currency_package_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param virtual_currency_package_sku (REQUIRED) Virtual currency package SKU.
-- @param locale Response language. Two-letter lowercase language code per ISO 639-1.
-- @param country Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/) and [the process of determining the country](https://developers.xsolla.com/doc/in-game-store/features/pricing-policy/#pricing_policy_country_determination).
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_virtual_currency_package_sku(project_id, virtual_currency_package_sku, locale, country, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(virtual_currency_package_sku)

    local url_path = "/v2/project/{project_id}/items/virtual_currency/package/sku/{virtual_currency_package_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{virtual_currency_package_sku}", uri.encode(virtual_currency_package_sku))

    local query_params = {}
    query_params["locale"] = locale
    query_params["country"] = country
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get items list by specified group
-- Gets an items list from the specified group for building a catalog.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
--  Note
-- 
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- /v2/project/{project_id}/items/virtual_items/group/{external_id}
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
function M.get_virtual_items_group(project_id, external_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/items/virtual_items/group/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get items groups list
-- Gets an items groups list for building a catalog.
-- /v2/project/{project_id}/items/groups
-- @name get_item_groups
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_item_groups(project_id, promo_code, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items/groups"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create order with specified item purchased by virtual currency
-- Creates item purchase using virtual currency.
-- /v2/project/{project_id}/payment/item/{item_sku}/virtual/{virtual_currency_sku}
-- @name create_order_with_item_for_virtual_currency
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param virtual_currency_sku (REQUIRED) Virtual currency SKU.
-- @param platform Publishing platform the user plays on: `xsolla` (default), `playstation_network`, `xbox_live`, `pc_standalone`, `nintendo_shop`, `google_play`, `app_store_ios`, `android_standalone`, `ios_standalone`, `android_other`, `ios_other`, `pc_other`.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_order_with_item_for_virtual_currency(project_id, item_sku, virtual_currency_sku, platform, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)
    assert(virtual_currency_sku)

    local url_path = "/v2/project/{project_id}/payment/item/{item_sku}/virtual/{virtual_currency_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))
    url_path = url_path:gsub("{virtual_currency_sku}", uri.encode(virtual_currency_sku))

    local query_params = {}
    query_params["platform"] = platform

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get sellable items list
-- Gets a sellable items list for building a catalog.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
--  Note
-- 
-- In general, the use of catalog of items is available without authorization.
--  Only authorized users can get a personalized catalog.
-- /v2/project/{project_id}/items
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
function M.get_sellable_items(project_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/items"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get sellable item by ID
-- Gets a sellable item by its ID.
-- Note
-- 
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- /v2/project/{project_id}/items/id/{item_id}
-- @name get_sellable_item_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_sellable_item_by_id(project_id, item_id, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/items/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_id}", uri.encode(item_id))

    local query_params = {}
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get sellable item by SKU
-- Gets a sellable item by SKU for building a catalog.
-- Note
-- 
-- This endpoint, accessible without authorization, returns generic data. However, authorization enriches the response with user-specific details for a personalized result, such as available user limits and promotions.
-- /v2/project/{project_id}/items/sku/{sku}
-- @name get_sellable_item_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param sku (REQUIRED) Item SKU.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param show_inactive_time_limited_items Shows time-limited items that are not available to the user. The validity period of such items has not started or has already expired.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_sellable_item_by_sku(project_id, sku, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(sku)

    local url_path = "/v2/project/{project_id}/items/sku/{sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{sku}", uri.encode(sku))

    local query_params = {}
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get sellable items list by specified group
-- Gets a sellable items list from the specified group for building a catalog.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields. 
--  Note
-- 
-- In general, the use of catalog of items is available without authorization.
--  Only authorized users can get a personalized catalog.
-- /v2/project/{project_id}/items/group/{external_id}
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
function M.get_sellable_items_group(project_id, external_id, limit, offset, locale, additional_fields, country, promo_code, show_inactive_time_limited_items, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/items/group/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of regions
-- Gets list of regions.
-- 
-- You can use a region for managing your regional restrictions.
-- /v2/project/{project_id}/admin/region
-- @name admin_get_regions
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_regions(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/region"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create region
-- Creates region.
-- 
-- You can use a region for managing your regional restrictions.
-- /v2/project/{project_id}/admin/region
-- @name admin_create_region
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_region(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/region"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get region
-- Gets particular region.
-- 
-- You can use a region for managing your regional restrictions.
-- /v2/project/{project_id}/admin/region/{region_id}
-- @name admin_get_region
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param region_id (REQUIRED) Region ID. Unique region identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_region(project_id, region_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(region_id)

    local url_path = "/v2/project/{project_id}/admin/region/{region_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{region_id}", uri.encode(region_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update region
-- Updates particular region.
-- 
-- You can use a region for managing your regional restrictions.
-- /v2/project/{project_id}/admin/region/{region_id}
-- @name admin_update_region
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param region_id (REQUIRED) Region ID. Unique region identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_region(project_id, region_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(region_id)

    local url_path = "/v2/project/{project_id}/admin/region/{region_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{region_id}", uri.encode(region_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete region
-- Deletes particular region.
-- /v2/project/{project_id}/admin/region/{region_id}
-- @name admin_delete_region
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param region_id (REQUIRED) Region ID. Unique region identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_region(project_id, region_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(region_id)

    local url_path = "/v2/project/{project_id}/admin/region/{region_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{region_id}", uri.encode(region_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Refresh all purchase limits for specified user
-- Refreshes all purchase limits across all items for a specified user so they can purchase these items again.
-- 
-- User limit API allows you to sell an item in a limited quantity. To configure the purchase limits, go to the Admin section of the desired item type module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp;amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- /v2/project/{project_id}/admin/user/limit/item/all
-- @name reset_all_user_items_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.reset_all_user_items_limit(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/item/all"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Refresh purchase limit
-- Refreshes the purchase limit for an item so a user can buy it again. If the *user* parameter is `null`, this call refreshes this limit for all users.
-- 
-- User limit API allows you to sell an item in a limited quantity. To configure the purchase limits, go to the Admin section of the desired item type module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp;amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- /v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}/all
-- @name reset_user_item_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.reset_user_item_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}/all"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get number of items available to specified user
-- Gets the remaining number of items available to the specified user within the limit applied.
-- 
-- User limit API allows you to sell an item in a limited quantity. To configure the purchase limits, go to the Admin section of the desired item type module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp;amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- /v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}
-- @name get_user_item_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param user_external_id (REQUIRED) User external ID
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_user_item_limit(project_id, item_sku, user_external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)
    assert(user_external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}
    query_params["user_external_id"] = user_external_id

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Increase number of items available to specified user
-- Increases the remaining number of items available to the specified user within the limit applied.
-- 
-- User limit API allows you to sell an item in a limited quantity. To configure the purchase limits, go to the Admin section of the desired item type module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp;amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- /v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}
-- @name add_user_item_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.add_user_item_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Set number of items available to specified user
-- Sets the number of items the specified user can buy within the limit applied after it was increased or decreased.
-- 
-- User limit API allows you to sell an item in a limited quantity. To configure the purchase limits, go to the Admin section of the desired item type module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp;amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- /v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}
-- @name set_user_item_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.set_user_item_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Decrease number of items available to specified user
-- Decreases the remaining number of items available to the specified user within the limit applied.
-- 
-- User limit API allows you to sell an item in a limited quantity. To configure the purchase limits, go to the Admin section of the desired item type module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp;amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- /v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}
-- @name remove_user_item_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.remove_user_item_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Refresh all promotion limits for specified user
-- Refreshes all limits across all promotions for the specified user so they can use these promotions again.
-- 
-- User limit API allows you to limit the number of times users can use a promotion. For configuring the user limit itself, go to the Admin section of the desired promotion type:
-- * [Discount Promotions](https://developers.xsolla.com/api/igs/tag/promotions-discounts/)
-- * [Bonus Promotions](https://developers.xsolla.com/api/igs/tag/promotions-bonuses/)
-- /v2/project/{project_id}/admin/user/limit/promotion/all
-- @name reset_all_user_promotions_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.reset_all_user_promotions_limit(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promotion/all"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Refresh promotion limit for users
-- Refreshes the promotion limit so a user can use this promotion again. If the *user* parameter is `null`, this call refreshes this limit for all users.
-- 
-- User limit API allows you to limit the number of times users can use a promotion. For configuring the user limit itself, go to the Admin section of the desired promotion type:
-- * [Discount Promotions](https://developers.xsolla.com/api/igs/tag/promotions-discounts/)
-- * [Bonus Promotions](https://developers.xsolla.com/api/igs/tag/promotions-bonuses/)
-- /v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}/all
-- @name reset_user_promotion_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promotion_id (REQUIRED) Promotion ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.reset_user_promotion_limit(project_id, promotion_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}/all"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promotion_id}", uri.encode(promotion_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get promotion limit for specified user
-- Gets the remaining number of times the specified user can use the promotion within the limit applied.
-- 
-- User limit API allows you to limit the number of times users can use a promotion. For configuring the user limit itself, go to the Admin section of the desired promotion type:
-- * [Discount Promotions](https://developers.xsolla.com/api/igs/tag/promotions-discounts/)
-- * [Bonus Promotions](https://developers.xsolla.com/api/igs/tag/promotions-bonuses/)
-- /v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}
-- @name get_user_promotion_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promotion_id (REQUIRED) Promotion ID. Unique promotion identifier within the project.
-- @param user_external_id (REQUIRED) User external ID
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_user_promotion_limit(project_id, promotion_id, user_external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(promotion_id)
    assert(user_external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promotion_id}", uri.encode(promotion_id))

    local query_params = {}
    query_params["user_external_id"] = user_external_id

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Increase promotion limit for specified user
-- Increases the remaining number of times the specified user can use the promotion within the limit applied.
-- 
-- User limit API allows you to limit the number of times users can use a promotion. For configuring the user limit itself, go to the Admin section of the desired promotion type:
-- * [Discount Promotions](https://developers.xsolla.com/api/igs/tag/promotions-discounts/)
-- * [Bonus Promotions](https://developers.xsolla.com/api/igs/tag/promotions-bonuses/)
-- /v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}
-- @name add_user_promotion_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promotion_id (REQUIRED) Promotion ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.add_user_promotion_limit(project_id, promotion_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promotion_id}", uri.encode(promotion_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Set promotion limit for specified user
-- Sets the number of times the specified user can use a promotion within the limit applied after it was increased or decreased.
-- 
-- User limit API allows you to limit the number of times users can use a promotion. For configuring the user limit itself, go to the Admin section of the desired promotion type:
-- * [Discount Promotions](https://developers.xsolla.com/api/igs/tag/promotions-discounts/)
-- * [Bonus Promotions](https://developers.xsolla.com/api/igs/tag/promotions-bonuses/)
-- /v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}
-- @name set_user_promotion_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promotion_id (REQUIRED) Promotion ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.set_user_promotion_limit(project_id, promotion_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promotion_id}", uri.encode(promotion_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Decrease promotion limit for specified user
-- Decreases the remaining number of times the specified user can use a promotion within the limit applied.
-- 
-- User limit API allows you to limit the number of times users can use a promotion. For configuring the user limit itself, go to the Admin section of the desired promotion type:
-- * [Discount Promotions](https://developers.xsolla.com/api/igs/tag/promotions-discounts/)
-- * [Bonus Promotions](https://developers.xsolla.com/api/igs/tag/promotions-bonuses/)
-- /v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}
-- @name remove_user_promotion_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param promotion_id (REQUIRED) Promotion ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.remove_user_promotion_limit(project_id, promotion_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{promotion_id}", uri.encode(promotion_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get promo code limit for specified user
-- Gets the remaining number of times the specified user can use the promo code.
-- 
-- User limit API allows you to limit the number of times users can use a promo code. For configuring the user limit itself, go to the Admin section:
-- * [Promo Codes](https://developers.xsolla.com/api/igs/tag/promotions-promo-codes/)
-- /v2/project/{project_id}/admin/user/limit/promocode/external_id/{external_id}
-- @name get_promo_code_user_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param user_external_id (REQUIRED) User external ID
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_promo_code_user_limit(project_id, external_id, user_external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)
    assert(user_external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promocode/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["user_external_id"] = user_external_id

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Increase promo code limit for specified user
-- Increases the remaining number of times the specified user can use the promo code.
-- 
-- User limit API allows you to limit the number of times users can use a promo code. For configuring the user limit itself, go to the Admin section:
-- * [Promo Codes](https://developers.xsolla.com/api/igs/tag/promotions-promo-codes/)
-- /v2/project/{project_id}/admin/user/limit/promocode/external_id/{external_id}
-- @name add_promo_code_user_promotion_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.add_promo_code_user_promotion_limit(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promocode/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Set promo code limit for specified user
-- Sets the number of times the specified user can use a promo code after it was increased or decreased.
-- 
-- User limit API allows you to limit the number of times users can use a promo code. For configuring the user limit itself, go to the Admin section:
-- * [Promo Codes](https://developers.xsolla.com/api/igs/tag/promotions-promo-codes/)
-- /v2/project/{project_id}/admin/user/limit/promocode/external_id/{external_id}
-- @name set_promo_code_user_promotion_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.set_promo_code_user_promotion_limit(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promocode/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Decrease promo code limit for specified user
-- Decreases the remaining number of times the specified user can use a promo code.
-- 
-- User limit API allows you to limit the number of times users can use a promo code. For configuring the user limit itself, go to the Admin section:
-- * [Promo Codes](https://developers.xsolla.com/api/igs/tag/promotions-promo-codes/)
-- /v2/project/{project_id}/admin/user/limit/promocode/external_id/{external_id}
-- @name remove_promo_code_user_promotion_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.remove_promo_code_user_promotion_limit(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promocode/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get coupon limit for specified user
-- Gets the remaining number of times the specified user can use the coupon.
-- 
-- User limit API allows you to limit the number of times users can use a coupon. For configuring the user limit itself, go to the Admin section:
-- * [Coupons](https://developers.xsolla.com/api/igs/tag/promotions-coupons/)
-- /v2/project/{project_id}/admin/user/limit/coupon/external_id/{external_id}
-- @name get_coupon_user_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param user_external_id (REQUIRED) User external ID
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_coupon_user_limit(project_id, external_id, user_external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)
    assert(user_external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/coupon/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["user_external_id"] = user_external_id

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Increase coupon limit for specified user
-- Increases the remaining number of times the specified user can use the coupon.
-- 
-- User limit API allows you to limit the number of times users can use a coupon. For configuring the user limit itself, go to the Admin section:
-- * [Coupons](https://developers.xsolla.com/api/igs/tag/promotions-coupons/)
-- /v2/project/{project_id}/admin/user/limit/coupon/external_id/{external_id}
-- @name add_coupon_user_promotion_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.add_coupon_user_promotion_limit(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/coupon/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Set coupon limit for specified user
-- Sets the number of times the specified user can use a coupon after it was increased or decreased.
-- 
-- User limit API allows you to limit the number of times users can use a coupon. For configuring the user limit itself, go to the Admin section:
-- * [Coupons](https://developers.xsolla.com/api/igs/tag/promotions-coupons/)
-- /v2/project/{project_id}/admin/user/limit/coupon/external_id/{external_id}
-- @name set_coupon_user_promotion_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.set_coupon_user_promotion_limit(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/coupon/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Decrease coupon limit for specified user
-- Decreases the remaining number of times the specified user can use a coupon.
-- 
-- User limit API allows you to limit the number of times users can use a coupon. For configuring the user limit itself, go to the Admin section:
-- * [Coupons](https://developers.xsolla.com/api/igs/tag/promotions-coupons/)
-- /v2/project/{project_id}/admin/user/limit/coupon/external_id/{external_id}
-- @name remove_coupon_user_promotion_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.remove_coupon_user_promotion_limit(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/coupon/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get promo code limit for codes
-- Gets the remaining number of times codes can be used. For filtering the codes, use the `codes` query parameter.
-- 
-- For configuring the code limit itself, go to the Admin section:
-- * [Promo Codes](https://developers.xsolla.com/api/igs/tag/promotions-promo-codes/)
-- /v2/project/{project_id}/admin/code/limit/promocode/external_id/{external_id}
-- @name get_promo_code_code_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param codes Unique case-sensitive codes. Contain only letters and numbers.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_promo_code_code_limit(project_id, external_id, codes, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/code/limit/promocode/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["codes"] = codes
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get unique coupon code limits
-- Gets the remaining number of times codes can be used. For filtering the codes, use the `codes` query parameter.
-- 
-- For configuring the code limit itself, go to the Admin section:
-- * [Coupons](https://developers.xsolla.com/api/igs/tag/promotions-coupons/)
-- /v2/project/{project_id}/admin/code/limit/coupon/external_id/{external_id}
-- @name get_coupon_code_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param codes Unique case-sensitive codes. Contain only letters and numbers.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_coupon_code_limit(project_id, external_id, codes, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/code/limit/coupon/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["codes"] = codes
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of value points for administration
-- Gets the list of value points within a project for administration.
-- /v2/project/{project_id}/admin/items/value_points
-- @name admin_get_value_points_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_value_points_list(project_id, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/value_points"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create value point
-- Creates a value point.
-- /v2/project/{project_id}/admin/items/value_points
-- @name admin_create_value_points
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_value_points(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/value_points"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get value point
-- Gets a value point by the SKU within a project for administration.
-- /v2/project/{project_id}/admin/items/value_points/sku/{item_sku}
-- @name admin_get_value_point
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_value_point(project_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/value_points/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update value point
-- Updates a value point identified by an SKU.
-- /v2/project/{project_id}/admin/items/value_points/sku/{item_sku}
-- @name admin_update_value_point
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_value_point(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/value_points/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete value points
-- Deletes a value point identified by an SKU.
-- /v2/project/{project_id}/admin/items/value_points/sku/{item_sku}
-- @name admin_delete_value_point
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_value_point(project_id, item_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/value_points/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{item_sku}", uri.encode(item_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of items with value points
-- Gets list of all items with value points within a project for administration.
-- /v2/project/{project_id}/admin/items/{value_point_sku}/value_points/rewards
-- @name admin_get_items_value_point_reward
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param value_point_sku (REQUIRED) Value Point SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_items_value_point_reward(project_id, value_point_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(value_point_sku)

    local url_path = "/v2/project/{project_id}/admin/items/{value_point_sku}/value_points/rewards"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{value_point_sku}", uri.encode(value_point_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Set value points for items
-- Assigns value points to one or several items by an SKU. Users receive value points after they purchase these items.
-- 
-- Note that this PUT request overwrites all previously set value points for items in the project.
-- 
-- To avoid unintentional deletion of value points, include all items and their respective value points in each PUT request.
-- 
-- If you only want to update the value points for a specific item while preserving the value points of other items, you should retrieve the current set of value points using a GET request, modify the desired item&amp;#x27;s value points, and then send the modified set of value points back with the updated value points for the specific item.
-- /v2/project/{project_id}/admin/items/{value_point_sku}/value_points/rewards
-- @name admin_set_items_value_point_reward
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param value_point_sku (REQUIRED) Value Point SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_set_items_value_point_reward(project_id, value_point_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(value_point_sku)

    local url_path = "/v2/project/{project_id}/admin/items/{value_point_sku}/value_points/rewards"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{value_point_sku}", uri.encode(value_point_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Partially update value points for items
-- Partially updates the number of value points for one or more items by the item’s SKU. Users receive these value points after purchasing the specified items.
-- 
-- Principles of updating value points:
--   * If an item does not yet have value points, sending a non-zero value in the `amount` field creates them.
--   * If an item already has value points, sending a non-zero value in the `amount` field updates them.
--   * If `amount` is set to 0, the existing value points for that item are deleted.
-- 
-- Unlike the `PUT` method ([Set value points for items](https://developers.xsolla.com/api/igs/operation/admin-set-items-value-point-reward/)), this `PATCH` method does not overwrite all existing value points for items in the project, it only updates the specified items.
-- 
-- A single request can update up to 100 items. Duplicate item SKUs cannot be included in the same request.
-- /v2/project/{project_id}/admin/items/{value_point_sku}/value_points/rewards
-- @name admin_patch_items_value_point_reward
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param value_point_sku (REQUIRED) Value Point SKU.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_patch_items_value_point_reward(project_id, value_point_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(value_point_sku)

    local url_path = "/v2/project/{project_id}/admin/items/{value_point_sku}/value_points/rewards"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{value_point_sku}", uri.encode(value_point_sku))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PATCH", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete value points from items
-- Removes value point rewards from ALL items.
-- /v2/project/{project_id}/admin/items/{value_point_sku}/value_points/rewards
-- @name admin_delete_items_value_point_reward
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param value_point_sku (REQUIRED) Value Point SKU.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_items_value_point_reward(project_id, value_point_sku, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(value_point_sku)

    local url_path = "/v2/project/{project_id}/admin/items/{value_point_sku}/value_points/rewards"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{value_point_sku}", uri.encode(value_point_sku))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get current user&#x27;s reward chains
-- Client endpoint. Gets the current user’s reward chains.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 50 items per response. To get more data page by page, use limit and offset fields.
-- /v2/project/{project_id}/user/reward_chain
-- @name get_reward_chains_list
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_reward_chains_list(project_id, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/user/reward_chain"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get current user&#x27;s value point balance
-- Client endpoint. Gets the current user’s value point balance.
-- /v2/project/{project_id}/user/reward_chain/{reward_chain_id}/balance
-- @name get_user_reward_chain_balance
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param reward_chain_id (REQUIRED) Reward chain ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_user_reward_chain_balance(project_id, reward_chain_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(reward_chain_id)

    local url_path = "/v2/project/{project_id}/user/reward_chain/{reward_chain_id}/balance"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(reward_chain_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Claim step reward
-- Client endpoint. Claims the current user’s step reward from a reward chain.
-- /v2/project/{project_id}/user/reward_chain/{reward_chain_id}/step/{step_id}/claim
-- @name claim_user_reward_chain_step_reward
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param reward_chain_id (REQUIRED) Reward chain ID.
-- @param step_id (REQUIRED) Reward chain step ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.claim_user_reward_chain_step_reward(project_id, reward_chain_id, step_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(reward_chain_id)
    assert(step_id)

    local url_path = "/v2/project/{project_id}/user/reward_chain/{reward_chain_id}/step/{step_id}/claim"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(reward_chain_id))
    url_path = url_path:gsub("{step_id}", uri.encode(step_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get top 10 contributors to reward chain under clan
-- Retrieves the list of top 10 contributors to the specific reward chain under the current user&amp;#x27;s clan. If a user doesn&amp;#x27;t belong to a clan, the call returns an empty array.
-- /v2/project/{project_id}/user/clan/contributors/{reward_chain_id}/top
-- @name get_user_clan_top_contributors
-- @param project_id (REQUIRED) Project ID.
-- @param reward_chain_id (REQUIRED) Reward chain ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_user_clan_top_contributors(project_id, reward_chain_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(reward_chain_id)

    local url_path = "/v2/project/{project_id}/user/clan/contributors/{reward_chain_id}/top"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(reward_chain_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update current user&#x27;s clan
-- Updates a current user&amp;#x27;s clan via user attributes. Claims all rewards from reward chains that were not claimed for a previous clan and returns them in the response. If the user was in a clan and now is not — their inclusion in the clan will be revoked. If the user changed the clan — the clan will be changed.
-- /v2/project/{project_id}/user/clan/update
-- @name user_clan_update
-- @param project_id (REQUIRED) Project ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.user_clan_update(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/user/clan/update"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of reward chains
-- Gets list of reward chains.
-- 
-- Attention
-- 
-- All projects have the limitation to the number of items that you can get in the response. The default and maximum value is 10 items per response. To get more data page by page, use limit and offset fields.
-- /v2/project/{project_id}/admin/reward_chain
-- @name admin_get_reward_chains
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param enabled Filter elements by `is_enabled` flag.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_reward_chains(project_id, limit, offset, enabled, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/reward_chain"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["enabled"] = enabled

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create reward chain
-- Creates reward chain.
-- /v2/project/{project_id}/admin/reward_chain
-- @name admin_create_reward_chain
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_reward_chain(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/reward_chain"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get reward chain
-- Gets particular reward chain.
-- /v2/project/{project_id}/admin/reward_chain/id/{reward_chain_id}
-- @name admin_get_reward_chain
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param reward_chain_id (REQUIRED) Reward chain ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_get_reward_chain(project_id, reward_chain_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(reward_chain_id)

    local url_path = "/v2/project/{project_id}/admin/reward_chain/id/{reward_chain_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(reward_chain_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update reward chain
-- Updates particular reward chain.
-- /v2/project/{project_id}/admin/reward_chain/id/{reward_chain_id}
-- @name admin_update_reward_chain
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param reward_chain_id (REQUIRED) Reward chain ID.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_reward_chain(project_id, reward_chain_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(reward_chain_id)

    local url_path = "/v2/project/{project_id}/admin/reward_chain/id/{reward_chain_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(reward_chain_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete reward chain
-- Deletes particular reward chain.
-- /v2/project/{project_id}/admin/reward_chain/id/{reward_chain_id}
-- @name admin_delete_reward_chain
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param reward_chain_id (REQUIRED) Reward chain ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_reward_chain(project_id, reward_chain_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(reward_chain_id)

    local url_path = "/v2/project/{project_id}/admin/reward_chain/id/{reward_chain_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(reward_chain_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Toggle reward chain
-- Enable/disable reward chain.
-- /v2/project/{project_id}/admin/reward_chain/id/{reward_chain_id}/toggle
-- @name admin_toggle_reward_chain
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param reward_chain_id (REQUIRED) Reward chain ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_toggle_reward_chain(project_id, reward_chain_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(reward_chain_id)

    local url_path = "/v2/project/{project_id}/admin/reward_chain/id/{reward_chain_id}/toggle"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(reward_chain_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Reset reward chain
-- Resets value points and progress of all users in the reward chain.
--  After the reset, you can update the validity period of the reward chain and the user can progress through it again.
-- Notice
--   
-- 
-- 
--   You should not reset the reward chain during its validity period. In this case, users may lose earned value points before they claim their reward.
-- 
-- /v2/project/{project_id}/admin/reward_chain/id/{reward_chain_id}/reset
-- @name admin_reset_reward_chain
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param reward_chain_id (REQUIRED) Reward chain ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_reset_reward_chain(project_id, reward_chain_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(reward_chain_id)

    local url_path = "/v2/project/{project_id}/admin/reward_chain/id/{reward_chain_id}/reset"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(reward_chain_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create unique catalog offer promotion
-- Creates a unique catalog offer promotion.
-- /v2/project/{project_id}/admin/unique_catalog_offer
-- @name admin_create_unique_catalog_offer
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_unique_catalog_offer(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get list of unique catalog offer promotions
-- Gets the list of unique catalog offer promotions of a project.
-- /v2/project/{project_id}/admin/unique_catalog_offer
-- @name get_unique_catalog_offers
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_unique_catalog_offers(project_id, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Update unique catalog offer promotion
-- Updates the unique catalog offer promotion.
-- /v2/project/{project_id}/admin/unique_catalog_offer/{external_id}
-- @name update_unique_catalog_offer_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_unique_catalog_offer_promotion(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get unique catalog offer promotion
-- Gets the specified unique catalog offer promotion.
-- /v2/project/{project_id}/admin/unique_catalog_offer/{external_id}
-- @name get_unique_catalog_offer
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_unique_catalog_offer(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Delete unique catalog offer promotion
-- Deletes [unique catalog offer promotion](https://developers.xsolla.com/doc/in-game-store/features/unique-offer/). The deleted promotion:
-- * Disappears from the list of promotions set up in your project.
-- * Is no longer applied to the item catalog and the cart. User can’t buy items with this promotion.
-- 
-- After deletion, the promotion can’t be restored.
-- /v2/project/{project_id}/admin/unique_catalog_offer/{external_id}
-- @name delete_unique_catalog_offer_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.delete_unique_catalog_offer_promotion(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Activate unique catalog offer promotion
-- Activates a unique catalog offer promotion.
-- The created unique catalog offer promotion is disabled by default.
-- It cannot be redeemed until you activate it.
-- Use this endpoint to enable and activate a coupon promotion.
-- /v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/activate
-- @name activate_unique_catalog_offer
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.activate_unique_catalog_offer(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/activate"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Deactivate unique catalog offer promotion
-- Deactivates a unique catalog offer promotion.
-- The created unique catalog offer promotion is disabled by default.
-- It cannot be redeemed until you activate it.
-- Use this endpoint to disable and deactivate a coupon promotion.
-- /v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/deactivate
-- @name deactivate_unique_catalog_offer
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.deactivate_unique_catalog_offer(project_id, external_id, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/deactivate"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Create unique catalog offer code
-- Creates unique catalog offer code.
-- /v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/code
-- @name create_unique_catalog_offer_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_unique_catalog_offer_code(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/code"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get unique catalog offer codes
-- Gets unique catalog offer codes.
-- /v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/code
-- @name get_unique_catalog_offer_codes
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param limit Limit for the number of elements on the page.
-- @param offset Number of the element from which the list is generated (the count starts from 0).
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_unique_catalog_offer_codes(project_id, external_id, limit, offset, callback, retry_policy, cancellation_token)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/code"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Generate unique catalog offer codes
-- Generates unique catalog offer codes.
-- /v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/code/generate
-- @name generate_unique_catalog_offer_codes
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.generate_unique_catalog_offer_codes(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/code/generate"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))
    url_path = url_path:gsub("{external_id}", uri.encode(external_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Import items via JSON file
-- Imports items into the store from a JSON file via the specified URL. Refer to the [documentation](https://developers.xsolla.com/doc/in-game-store/how-to/json-import/) for more information about import from a JSON file.
-- /v1/projects/{project_id}/import/from_external_file
-- @name import_items_from_external_file
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.import_items_from_external_file(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v1/projects/{project_id}/import/from_external_file"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = body


    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

--- Get status of items import
-- Retrieves information about the progress of importing items into the project. This API call retrieves data on the last import carried out through the API or Publisher Account.
-- /v1/admin/projects/{project_id}/connectors/import_items/import/status
-- @name get_items_import_status
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_items_import_status(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v1/admin/projects/{project_id}/connectors/import_items/import/status"
    url_path = url_path:gsub("{project_id}", uri.encode(project_id))

    local query_params = {}

    local post_data = nil


    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result)
        return result
  end)
end

return M