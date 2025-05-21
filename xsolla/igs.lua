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
    retry_policy = retries.fixed(5, 0.5),
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
local function http(callback, url_path, query_params, method, post_data, retry_policy, cancellation_token, handler_fn)
    if callback then
        log(url_path, "with callback")
        net.http(config, url_path, query_params, method, post_data, retry_policy, cancellation_token, function(result)
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
            net.http(config, url_path, query_params, method, post_data, retry_policy, cancellation_token, function(result)
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


--- Create create_update_attribute data structure
-- @param t Table with properties. Acceptable table keys:
--   * admin_attribute_external_id - [string] Unique attribute ID. The `external_id` may only contain lowercase Latin alphanumeric characters, dashes, and underscores.
--   * admin_attribute_name - [object] Object with localizations for attribute's name. Keys are specified in ISO 3166-1.
-- @example
-- {
--   external_id = "genre",
--   name = 
--   {
--     en = "Genre",
--     de = "Genre",
--   },
-- }

function M.body_create_update_attribute(t)
    assert(t)
    assert(t.external_id)
    assert(t.name)
    return json.encode({
        ["admin_attribute_external_id"] = t.admin_attribute_external_id,
        ["admin_attribute_name"] = t.admin_attribute_name,
    })
end


--- Create create_update_attribute_value data structure
-- @param t Table with properties. Acceptable table keys:
--   * value_external_id - [string] Unique value ID for an attribute. The `external_id` may only contain lowercase Latin alphanumeric characters, dashes, and underscores.
--   * value_name - [object] Object with localizations of the value's name. Keys are specified in ISO 3166-1.
-- @example
-- {
--   external_id = "weapon_class_sword_value",
--   value = 
--   {
--     en = "Sword",
--     de = "Schwert",
--   },
-- }

function M.body_create_update_attribute_value(t)
    assert(t)
    assert(t.external_id)
    assert(t.value)
    return json.encode({
        ["value_external_id"] = t.value_external_id,
        ["value_name"] = t.value_name,
    })
end


--- Create personalized_catalog_create_update_body data structure
-- @param t Table with properties. Acceptable table keys:
--   * name - [string] Readable name of a rule. Used to display a rule in Publisher Account.
--   * is_enabled - [boolean] If rule is enabled.
--   * is_satisfied_for_unauth - [boolean] Whether the item is displayed to unauthorized users. If `true`, the item is displayed to the unauthorized user regardless of catalog display rules. `false` by default.
--   * attribute_conditions - [oneof] 
--   * items - [array] 
-- @example
-- {
--   name = "Ork race armor rule",
--   is_enabled = true,
--   attribute_conditions = 
--   {
--     {
--       attribute = "race",
--       operator = "eq",
--       value = "ork",
--       type = "string",
--       can_be_missing = false,
--     },
--   },
--   items = 
--   {
--     {
--       item_id = 1,
--     },
--   },
--   is_satisfied_for_unauth = false,
-- }

function M.body_personalized_catalog_create_update_body(t)
    assert(t)
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


--- Create bundles_bundle data structure
-- @param t Table with properties. Acceptable table keys:
--   * bundles_sku - [string] Unique item ID. The SKU may only contain lowercase Latin alphanumeric characters, periods, dashes, and underscores.
--   * bundles_admin_name_two_letter_locale - [object] Object with localizations for item's name. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * bundles_groups_request - [array] Groups the item belongs to.
-- Note. The string value refers to group `external_id`.
--   * bundles_admin_post_put_attributes - [array] List of attributes.
-- Attention. You can't specify more than 20 attributes for the item. Any attempts to exceed the limit result in an error.
--   * bundles_admin_description_two_letter_locale - [object] Object with localizations for item's description. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * bundles_admin_long_description_two_letter_locale - [object] Object with localizations for long description of item. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * bundles_image_url - [string] Image URL.
--   * bundles_prices - [array] Prices in real currencies.
--   * vc_prices - [allof] The specified bundle.
--   * bundles_admin_content_request - [array] The specified bundle.
--   * value_is_free - [boolean] If `true`, the item is free.
--   * bundles_is_enabled - [boolean] If disabled, the item can't be found and purchased.
--   * bundles_is_show_in_store - [boolean] Item is available for purchase.
--   * media_list - [allof] The specified bundle.
--   * bundles_order - [integer] Bundle's order priority in the list.
--   * bundles_admin_regions - [array] The specified bundle.
--   * item_limit - [object] Item limits.
--   * item_periods - [array] Item sales period.
--   * item_custom_attributes - [object] A JSON object containing item attributes and values. Attributes allow you to add more info to items like the player's required level to use the item. Attributes enrich your game's internal logic and are accessible through dedicated GET methods and webhooks.
-- @example
-- {
--   sku = "com.xsolla.armour_chest_1",
--   name = 
--   {
--     en-US = "Chest of armour",
--     de-DE = "Brustpanzer",
--   },
--   is_enabled = true,
--   is_free = true,
--   order = 1,
--   long_description = 
--   {
--     en-US = "Chest of armour for soldiers",
--     de-DE = "Brustpanzer für Soldaten",
--   },
--   description = 
--   {
--     en-US = "Chest of armour for soldiers",
--     de-DE = "Brustpanzer für Soldaten",
--   },
--   image_url = "https://picture.bundle-with-many-stuff.png",
--   media_list = 
--   {
--     {
--       type = "image",
--       url = "https://test.com/image0",
--     },
--     {
--       type = "image",
--       url = "https://test.com/image1",
--     },
--   },
--   groups = 
--   {
--     "chests",
--   },
--   attributes = 
--   {
--     attributes = 
--     {
--       {
--         external_id = "class",
--         name = 
--         {
--           en-US = "Class",
--         },
--         values = 
--         {
--           {
--             external_id = "soldier",
--             value = 
--             {
--               en-US = "Soldier",
--             },
--           },
--           {
--             external_id = "officer",
--             value = 
--             {
--               en-US = "Officer",
--             },
--           },
--         },
--       },
--     },
--   },
--   prices = 
--   {
--     {
--       currency = "USD",
--       amount = 9.99,
--       is_default = true,
--       is_enabled = true,
--     },
--     {
--       currency = "EUR",
--       amount = 9.99,
--       is_default = false,
--       is_enabled = true,
--     },
--   },
--   vc_prices = nil,
--   content = 
--   {
--     {
--       sku = "com.xsolla.iron_gloves_1",
--       quantity = 1,
--     },
--     {
--       sku = "com.xsolla.iron_boots_1",
--       quantity = 1,
--     },
--     {
--       sku = "com.xsolla.iron_shield_1",
--       quantity = 1,
--     },
--     {
--       sku = "com.xsolla.iron_armour_1",
--       quantity = 1,
--     },
--     {
--       sku = "com.xsolla.iron_helmet_1",
--       quantity = 1,
--     },
--   },
--   limits = 
--   {
--     per_user = nil,
--     per_item = nil,
--   },
--   periods = 
--   {
--     {
--       date_from = "2020-08-11T10:00:00+03:00",
--       date_until = "2020-08-11T20:00:00+03:00",
--     },
--   },
--   custom_attributes = 
--   {
--     type = "lootbox",
--     purchased = 0,
--   },
-- }

function M.body_bundles_bundle(t)
    assert(t)
    assert(t.sku)
    assert(t.name)
    assert(t.description)
    return json.encode({
        ["bundles_sku"] = t.bundles_sku,
        ["bundles_admin_name_two_letter_locale"] = t.bundles_admin_name_two_letter_locale,
        ["bundles_groups_request"] = t.bundles_groups_request,
        ["bundles_admin_post_put_attributes"] = t.bundles_admin_post_put_attributes,
        ["bundles_admin_description_two_letter_locale"] = t.bundles_admin_description_two_letter_locale,
        ["bundles_admin_long_description_two_letter_locale"] = t.bundles_admin_long_description_two_letter_locale,
        ["bundles_image_url"] = t.bundles_image_url,
        ["bundles_prices"] = t.bundles_prices,
        ["vc_prices"] = t.vc_prices,
        ["bundles_admin_content_request"] = t.bundles_admin_content_request,
        ["value_is_free"] = t.value_is_free,
        ["bundles_is_enabled"] = t.bundles_is_enabled,
        ["bundles_is_show_in_store"] = t.bundles_is_show_in_store,
        ["media_list"] = t.media_list,
        ["bundles_order"] = t.bundles_order,
        ["bundles_admin_regions"] = t.bundles_admin_regions,
        ["item_limit"] = t.item_limit,
        ["item_periods"] = t.item_periods,
        ["item_custom_attributes"] = t.item_custom_attributes,
    })
end


--- Create cart_payment_fill_cart_json_model data structure
-- @param t Table with properties. Acceptable table keys:
--   * items - [array] List of items.
-- @example

function M.body_cart_payment_fill_cart_json_model(t)
    assert(t)
    assert(t.items)
    return json.encode({
        ["items"] = t.items,
    })
end


--- Create cart_payment_put_item_by_cart_idjsonmodel data structure
-- @param t Table with properties. Acceptable table keys:
--   * quantity - [number] Item quantity.
-- @example

function M.body_cart_payment_put_item_by_cart_idjsonmodel(t)
    assert(t)
    return json.encode({
        ["quantity"] = t.quantity,
    })
end


--- Create cart_payment_create_order_by_cart_idjsonmodel data structure
-- @param t Table with properties. Acceptable table keys:
--   * currency - [string] Order price currency. Three-letter currency code per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). Check the documentation for detailed information about [currencies supported by Xsolla](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/).
--   * locale - [string] Response language.
--   * sandbox - [boolean] Creates an order in the sandbox mode. The option is available for those users who are specified in the list of company users.
--   * settings - [object] Settings for configuring payment process and the payment UI for a user.
--   * custom_parameters - [object] Project specific parameters.
-- @example
-- {
--   sandbox = true,
--   settings = 
--   {
--     ui = 
--     {
--       theme = "63295a9a2e47fab76f7708e1",
--       desktop = 
--       {
--         header = 
--         {
--           is_visible = true,
--           visible_logo = true,
--           visible_name = true,
--           visible_purchase = true,
--           type = "normal",
--           close_button = false,
--         },
--       },
--     },
--   },
--   custom_parameters = 
--   {
--     character_id = "ingameUsername",
--   },
-- }

function M.body_cart_payment_create_order_by_cart_idjsonmodel(t)
    assert(t)
    return json.encode({
        ["currency"] = t.currency,
        ["locale"] = t.locale,
        ["sandbox"] = t.sandbox,
        ["settings"] = t.settings,
        ["custom_parameters"] = t.custom_parameters,
    })
end


--- Create cart_payment_create_order_with_specified_item_idjsonmodel data structure
-- @param t Table with properties. Acceptable table keys:
--   * currency - [string] Order price currency. Three-letter currency code per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). Check the documentation for detailed information about [currencies supported by Xsolla](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/).
--   * locale - [string] Response language.
--   * sandbox - [boolean] Creates an order in the sandbox mode. The option is available for those users who are specified in the list of company users.
--   * quantity - [integer] Item quantity.
--   * promo_code - [string] Redeems a code of a promo code promotion with payment.
--   * settings - [object] Settings for configuring payment process and the payment UI for a user.
--   * custom_parameters - [object] Project specific parameters.
-- @example
-- {
--   sandbox = true,
--   quantity = 5,
--   promo_code = "discount_code",
--   settings = 
--   {
--     ui = 
--     {
--       theme = "63295a9a2e47fab76f7708e1",
--       desktop = 
--       {
--         header = 
--         {
--           is_visible = true,
--           visible_logo = true,
--           visible_name = true,
--           visible_purchase = true,
--           type = "normal",
--           close_button = false,
--         },
--       },
--     },
--   },
--   custom_parameters = 
--   {
--     character_id = "ingameUsername",
--   },
-- }

function M.body_cart_payment_create_order_with_specified_item_idjsonmodel(t)
    assert(t)
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


--- Create admin_order_search data structure
-- @param t Table with properties. Acceptable table keys:
--   * limit - [integer] A limit on the number of orders included in the response.
--   * offset - [integer] Number of the order from which the list is generated (the count starts from 0).
--   * created_date_from - [string] Start date or date-time of the order creation period per [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601).
--   * created_date_until - [string] End date or date-time of the order creation period per [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601).
-- @example
-- {
--   offset = 0,
--   limit = 5,
--   created_date_from = "2018-01-07",
--   created_date_until = "2018-01-09T16:00:00+03:00",
-- }

function M.body_admin_order_search(t)
    assert(t)
    return json.encode({
        ["limit"] = t.limit,
        ["offset"] = t.offset,
        ["created_date_from"] = t.created_date_from,
        ["created_date_until"] = t.created_date_until,
    })
end


--- Create cart_payment_admin_create_payment_token data structure
-- @param t Table with properties. Acceptable table keys:
--   * cart_payment_settings_sandbox - [boolean] Set to `true` to test out the payment process. In this case, use https://sandbox-secure.xsolla.com to access the test payment UI.
--   * cart_payment_admin_user_request_body - [object] 
--   * cart_admin_payment - [object] 
--   * settings - [object] Settings for configuring payment process and the payment UI for a user.
--   * cart_payment_custom_parameters - [object] Your custom parameters represented as a valid JSON set of key-value pairs.
-- 
-- You can pass additional parameters through this field to configure anti-fraud filters. [See Pay Station documentation](https://developers.xsolla.com/doc/pay-station/features/antifraud/).
-- @example

function M.body_cart_payment_admin_create_payment_token(t)
    assert(t)
    assert(t.user)
    assert(t.purchase)
    return json.encode({
        ["cart_payment_settings_sandbox"] = t.cart_payment_settings_sandbox,
        ["cart_payment_admin_user_request_body"] = t.cart_payment_admin_user_request_body,
        ["cart_admin_payment"] = t.cart_admin_payment,
        ["settings"] = t.settings,
        ["cart_payment_custom_parameters"] = t.cart_payment_custom_parameters,
    })
end


--- Create cart_payment_admin_fill_cart_json_model data structure
-- @param t Table with properties. Acceptable table keys:
--   * country - [string] Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2). Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/). 
-- Example: `country=US`
--   * currency - [string] The item price currency displayed in the cart. Three-letter code per [ISO 4217](https://en.wikipedia.org/wiki/ISO_4217). Check the documentation for detailed information about [currencies supported by Xsolla](https://developers.xsolla.com/doc/pay-station/references/supported-currencies/).
--   * items - [array] 
-- @example

function M.body_cart_payment_admin_fill_cart_json_model(t)
    assert(t)
    assert(t.items)
    return json.encode({
        ["country"] = t.country,
        ["currency"] = t.currency,
        ["items"] = t.items,
    })
end


--- Create update_upsell data structure
-- @param t Table with properties.
-- @example

function M.body_update_upsell(t)
    assert(t)
    return json.encode(t)
end


--- Create create_upsell data structure
-- @param t Table with properties.
-- @example

function M.body_create_upsell(t)
    assert(t)
    return json.encode(t)
end


--- Create game_keys_create_update_game_model data structure
-- @param t Table with properties. Acceptable table keys:
--   * sku - [string] Unique item ID. The SKU may only contain lowercase Latin alphanumeric characters, periods, dashes, and underscores.
--   * game_keys_admin_name_two_letter_locale - [object] Object with localizations for item's name. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * game_keys_admin_description_two_letter_locale - [object] Object with localizations for item's description. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * game_keys_admin_long_description_two_letter_locale - [object] Object with localizations for long description of item. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * image_url - [string] Image URL.
--   * media_list - [array] Game additional assets such as screenshots, gameplay video, etc.
--   * order - [integer] Game order priority in the list.
--   * groups - [array] Groups the item belongs to.
--   * game_keys_admin_post_put_attributes - [array] List of attributes.
-- Attention. You can't specify more than 20 attributes for the item. Any attempts to exceed the limit result in an error.
--   * is_enabled - [boolean] If disabled, item cannot be purchased and accessed through inventory.
--   * is_show_in_store - [boolean] Item is available for purchase.
--   * unit_items - [array] Game keys for different DRMs.
-- @example

function M.body_game_keys_create_update_game_model(t)
    assert(t)
    assert(t.sku)
    assert(t.name)
    assert(t.unit_items)
    return json.encode({
        ["sku"] = t.sku,
        ["game_keys_admin_name_two_letter_locale"] = t.game_keys_admin_name_two_letter_locale,
        ["game_keys_admin_description_two_letter_locale"] = t.game_keys_admin_description_two_letter_locale,
        ["game_keys_admin_long_description_two_letter_locale"] = t.game_keys_admin_long_description_two_letter_locale,
        ["image_url"] = t.image_url,
        ["media_list"] = t.media_list,
        ["order"] = t.order,
        ["groups"] = t.groups,
        ["game_keys_admin_post_put_attributes"] = t.game_keys_admin_post_put_attributes,
        ["is_enabled"] = t.is_enabled,
        ["is_show_in_store"] = t.is_show_in_store,
        ["unit_items"] = t.unit_items,
    })
end


--- Create physical_items_create_update_physical_good_model data structure
-- @param t Table with properties. Acceptable table keys:
--   * sku - [string] Object with physical good data.
--   * physical_items_admin_name_two_letter_locale - [object] Object with localizations for item's name. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * physical_items_admin_description_two_letter_locale - [object] Object with localizations for item's description. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * physical_items_admin_long_description_two_letter_locale - [object] Object with localizations for long description of item. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * image_url - [string] Object with physical good data.
--   * media_list - [array] Object with physical good data.
--   * groups - [array] Object with physical good data.
--   * physical_items_admin_post_put_attributes - [array] List of attributes.
-- Attention. You can't specify more than 20 attributes for the item. Any attempts to exceed the limit result in an error.
--   * physical_items_admin_prices - [array] Object with physical good data.
--   * physical_items_admin_create_vc_prices - [array] Object with physical good data.
--   * is_enabled - [boolean] Object with physical good data.
--   * is_deleted - [boolean] Object with physical good data.
--   * value_is_free - [boolean] If `true`, the item is free.
--   * order - [number] Object with physical good data.
--   * tax_categories - [array] Object with physical good data.
--   * physical_items_admin_pre_order - [object] Object with physical good data.
--   * physical_items_admin_regions - [array] Object with physical good data.
--   * weight - [object] Weight of the item.
--   * item_limit - [object] Item limits.
-- @example
-- {
--   sku = "com.xsolla.t-shirt_1",
--   name = 
--   {
--     en = "T-Shirt",
--     de = "T-Shirt",
--   },
--   is_enabled = true,
--   is_free = false,
--   order = 1,
--   description = 
--   {
--     en = "Short Sleeve T-shirt",
--     de = "Kurzarm-T-Shirt",
--   },
--   attributes = 
--   {
--     {
--       external_id = "Color",
--       name = 
--       {
--         en = "Color",
--       },
--       values = 
--       {
--         {
--           external_id = "Color-black",
--           value = 
--           {
--             en-US = "Black",
--           },
--         },
--       },
--     },
--   },
--   prices = 
--   {
--     {
--       amount = 20,
--       currency = "EUR",
--       is_enabled = true,
--       is_default = false,
--     },
--     {
--       amount = 35,
--       currency = "USD",
--       is_enabled = true,
--       is_default = true,
--     },
--   },
--   tax_categories = 
--   {
--     "PG00005",
--   },
--   limits = 
--   {
--     per_user = 
--     {
--       total = 5,
--     },
--     per_item = nil,
--   },
-- }

function M.body_physical_items_create_update_physical_good_model(t)
    assert(t)
    assert(t.sku)
    return json.encode({
        ["sku"] = t.sku,
        ["physical_items_admin_name_two_letter_locale"] = t.physical_items_admin_name_two_letter_locale,
        ["physical_items_admin_description_two_letter_locale"] = t.physical_items_admin_description_two_letter_locale,
        ["physical_items_admin_long_description_two_letter_locale"] = t.physical_items_admin_long_description_two_letter_locale,
        ["image_url"] = t.image_url,
        ["media_list"] = t.media_list,
        ["groups"] = t.groups,
        ["physical_items_admin_post_put_attributes"] = t.physical_items_admin_post_put_attributes,
        ["physical_items_admin_prices"] = t.physical_items_admin_prices,
        ["physical_items_admin_create_vc_prices"] = t.physical_items_admin_create_vc_prices,
        ["is_enabled"] = t.is_enabled,
        ["is_deleted"] = t.is_deleted,
        ["value_is_free"] = t.value_is_free,
        ["order"] = t.order,
        ["tax_categories"] = t.tax_categories,
        ["physical_items_admin_pre_order"] = t.physical_items_admin_pre_order,
        ["physical_items_admin_regions"] = t.physical_items_admin_regions,
        ["weight"] = t.weight,
        ["item_limit"] = t.item_limit,
    })
end


--- Create physical_items_patch_physical_good_model data structure
-- @param t Table with properties. Acceptable table keys:
--   * sku - [string] Object with physical good data.
--   * physical_items_admin_name_two_letter_locale - [object] Object with localizations for item's name. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * physical_items_admin_description_two_letter_locale - [object] Object with localizations for item's description. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * physical_items_admin_long_description_two_letter_locale - [object] Object with localizations for long description of item. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * image_url - [string] Object with physical good data.
--   * media_list - [array] Object with physical good data.
--   * groups - [array] Object with physical good data.
--   * physical_items_admin_post_put_attributes - [array] List of attributes.
-- Attention. You can't specify more than 20 attributes for the item. Any attempts to exceed the limit result in an error.
--   * physical_items_admin_prices - [array] Object with physical good data.
--   * physical_items_admin_create_vc_prices - [array] Object with physical good data.
--   * is_enabled - [boolean] Object with physical good data.
--   * is_deleted - [boolean] Object with physical good data.
--   * value_is_free - [boolean] If `true`, the item is free.
--   * order - [number] Object with physical good data.
--   * tax_categories - [array] Object with physical good data.
--   * physical_items_admin_pre_order - [object] Object with physical good data.
--   * physical_items_admin_regions - [array] Object with physical good data.
--   * weight - [object] Weight of the item.
--   * item_limit - [object] Item limits.
-- @example

function M.body_physical_items_patch_physical_good_model(t)
    assert(t)
    assert(t.True)
    return json.encode({
        ["sku"] = t.sku,
        ["physical_items_admin_name_two_letter_locale"] = t.physical_items_admin_name_two_letter_locale,
        ["physical_items_admin_description_two_letter_locale"] = t.physical_items_admin_description_two_letter_locale,
        ["physical_items_admin_long_description_two_letter_locale"] = t.physical_items_admin_long_description_two_letter_locale,
        ["image_url"] = t.image_url,
        ["media_list"] = t.media_list,
        ["groups"] = t.groups,
        ["physical_items_admin_post_put_attributes"] = t.physical_items_admin_post_put_attributes,
        ["physical_items_admin_prices"] = t.physical_items_admin_prices,
        ["physical_items_admin_create_vc_prices"] = t.physical_items_admin_create_vc_prices,
        ["is_enabled"] = t.is_enabled,
        ["is_deleted"] = t.is_deleted,
        ["value_is_free"] = t.value_is_free,
        ["order"] = t.order,
        ["tax_categories"] = t.tax_categories,
        ["physical_items_admin_pre_order"] = t.physical_items_admin_pre_order,
        ["physical_items_admin_regions"] = t.physical_items_admin_regions,
        ["weight"] = t.weight,
        ["item_limit"] = t.item_limit,
    })
end


--- Create promotions_redeem_coupon_model data structure
-- @param t Table with properties. Acceptable table keys:
--   * coupon_code - [string] Unique coupon code. Contains letters and numbers.
--   * promotions_selected_unit_items - [object] The reward that is selected by a user.
-- Object key is an SKU of a unit, and value is an SKU of one of the items in a unit.
-- @example

function M.body_promotions_redeem_coupon_model(t)
    assert(t)
    return json.encode({
        ["coupon_code"] = t.coupon_code,
        ["promotions_selected_unit_items"] = t.promotions_selected_unit_items,
    })
end


--- Create promotions_coupon_create data structure
-- @param t Table with properties. Acceptable table keys:
--   * promotions_coupon_external_id - [string] Unique promotion ID. The `external_id` may only contain lowercase Latin alphanumeric characters, periods, dashes, and underscores.
--   * promotions_coupon_date_start - [string] Date when your promotion will be started.
--   * promotions_coupon_date_end - [string] Date when your promotion will be finished. Can be `null`.  If `date_end` is `null`, promotion will be unlimited by time.
--   * promotions_coupon_name - [object] Name of promotion. Should contain key/value pairs
-- where key is a locale with "^[a-z]{2}-[A-Z]{2}$" format, value is string.
--   * promotions_coupon_bonus - [array] 
--   * promotions_coupon_redeem_total_limit - [integer] Limits total numbers of coupons.
--   * promotions_coupon_redeem_user_limit - [integer] Limits total numbers of coupons redeemed by single user.
--   * promotions_redeem_code_limit - [integer] Number of redemptions per code.
--   * attribute_conditions - [oneof] Conditions which are compared to user attribute values.
-- All conditions must be met for the action to take an effect.
-- @example

function M.body_promotions_coupon_create(t)
    assert(t)
    assert(t.external_id)
    assert(t.name)
    return json.encode({
        ["promotions_coupon_external_id"] = t.promotions_coupon_external_id,
        ["promotions_coupon_date_start"] = t.promotions_coupon_date_start,
        ["promotions_coupon_date_end"] = t.promotions_coupon_date_end,
        ["promotions_coupon_name"] = t.promotions_coupon_name,
        ["promotions_coupon_bonus"] = t.promotions_coupon_bonus,
        ["promotions_coupon_redeem_total_limit"] = t.promotions_coupon_redeem_total_limit,
        ["promotions_coupon_redeem_user_limit"] = t.promotions_coupon_redeem_user_limit,
        ["promotions_redeem_code_limit"] = t.promotions_redeem_code_limit,
        ["attribute_conditions"] = t.attribute_conditions,
    })
end


--- Create promotions_coupon_update data structure
-- @param t Table with properties. Acceptable table keys:
--   * promotions_coupon_date_start - [string] Date when your promotion will be started.
--   * promotions_coupon_date_end - [string] Date when your promotion will be finished. Can be `null`.  If `date_end` is `null`, promotion will be unlimited by time.
--   * promotions_coupon_name - [object] Name of promotion. Should contain key/value pairs
-- where key is a locale with "^[a-z]{2}-[A-Z]{2}$" format, value is string.
--   * promotions_coupon_bonus - [array] 
--   * promotions_coupon_redeem_total_limit - [integer] Limits total numbers of coupons.
--   * promotions_coupon_redeem_user_limit - [integer] Limits total numbers of coupons redeemed by single user.
--   * promotions_redeem_code_limit - [integer] Number of redemptions per code.
--   * attribute_conditions - [oneof] Conditions which are compared to user attribute values.
-- All conditions must be met for the action to take an effect.
-- @example

function M.body_promotions_coupon_update(t)
    assert(t)
    assert(t.name)
    return json.encode({
        ["promotions_coupon_date_start"] = t.promotions_coupon_date_start,
        ["promotions_coupon_date_end"] = t.promotions_coupon_date_end,
        ["promotions_coupon_name"] = t.promotions_coupon_name,
        ["promotions_coupon_bonus"] = t.promotions_coupon_bonus,
        ["promotions_coupon_redeem_total_limit"] = t.promotions_coupon_redeem_total_limit,
        ["promotions_coupon_redeem_user_limit"] = t.promotions_coupon_redeem_user_limit,
        ["promotions_redeem_code_limit"] = t.promotions_redeem_code_limit,
        ["attribute_conditions"] = t.attribute_conditions,
    })
end


--- Create promotions_create_coupon_promocode_code data structure
-- @param t Table with properties. Acceptable table keys:
--   * promotions_coupon_code - [string] Unique case sensitive code. Contains letters and numbers.
-- @example

function M.body_promotions_create_coupon_promocode_code(t)
    assert(t)
    return json.encode({
        ["promotions_coupon_code"] = t.promotions_coupon_code,
    })
end


--- Create promotions_redeem_promo_code_model data structure
-- @param t Table with properties. Acceptable table keys:
--   * coupon_code - [string] Unique code of promo code. Contains letters and numbers.
--   * cart - [object] 
--   * promotions_selected_unit_items - [object] The reward that is selected by a user.
-- Object key is an SKU of a unit, and value is an SKU of one of the items in a unit.
-- @example

function M.body_promotions_redeem_promo_code_model(t)
    assert(t)
    return json.encode({
        ["coupon_code"] = t.coupon_code,
        ["cart"] = t.cart,
        ["promotions_selected_unit_items"] = t.promotions_selected_unit_items,
    })
end


--- Create promotions_cancel_promo_code_model data structure
-- @param t Table with properties. Acceptable table keys:
--   * cart - [object] 
-- @example

function M.body_promotions_cancel_promo_code_model(t)
    assert(t)
    return json.encode({
        ["cart"] = t.cart,
    })
end


--- Create promotions_promocode_create data structure
-- @param t Table with properties. Acceptable table keys:
--   * promotions_coupon_external_id - [string] Unique promotion ID. The `external_id` may only contain lowercase Latin alphanumeric characters, periods, dashes, and underscores.
--   * promotions_coupon_date_start - [string] Date when your promotion will be started.
--   * promotions_coupon_date_end - [string] Date when your promotion will be finished. Can be `null`.  If `date_end` is `null`, promotion will be unlimited by time.
--   * promotions_coupon_name - [object] Name of promotion. Should contain key/value pairs
-- where key is a locale with "^[a-z]{2}-[A-Z]{2}$" format, value is string.
--   * promotions_coupon_bonus - [array] 
--   * promotions_coupon_redeem_total_limit - [integer] Limits total numbers of coupons.
--   * promotions_coupon_redeem_user_limit - [integer] Limits total numbers of coupons redeemed by single user.
--   * promotions_redeem_code_limit - [integer] Number of redemptions per code.
--   * discount - [object] 
--   * promotions_discounted_items - [array] List of items that are discounted by a promo code.
--   * attribute_conditions - [oneof] Conditions which are compared to user attribute values.
-- All conditions must be met for the action to take an effect.
--   * price_conditions_promocode - [array] Array of objects with conditions that set the price range for applying the promotion to the entire cart.
-- 
-- The total price of all items in the user's cart is compared with the price range specified in the condition. [Bonuses](/api/igs/operation/create-promo-code/#!path=bonus&t=request) and [discounts](/api/igs/operation/create-promo-code/#!path=discount&t=request) are applied to all items in the cart if the price of the cart meets the specified condition.
-- 
-- If you pass this array, set the value of the [discounted_items](/api/igs/operation/create-promo-code/#!path=discounted_items&t=request) array to `null`.
--   * item_price_conditions_promocode - [array] Array of objects with conditions that set the price range for applying the promotion to certain items in the cart.
-- 
-- The price of each item in the user's cart is compared with the price range specified in the condition. [Bonuses](/api/igs/operation/create-promo-code/#!path=bonus&t=request) and [discounts](/api/igs/operation/create-promo-code/#!path=discount&t=request) are applied only to those items in the cart whose price meets the condition.
-- 
-- If you pass this array, set the value of the [discounted_items](/api/igs/operation/create-promo-code/#!path=discounted_items&t=request) array to `null`.
--   * excluded_promotions - [array] List of promotion IDs to exclude when applying this promotion. 
-- Example: `[12, 789]`
-- @example

function M.body_promotions_promocode_create(t)
    assert(t)
    assert(t.external_id)
    assert(t.name)
    return json.encode({
        ["promotions_coupon_external_id"] = t.promotions_coupon_external_id,
        ["promotions_coupon_date_start"] = t.promotions_coupon_date_start,
        ["promotions_coupon_date_end"] = t.promotions_coupon_date_end,
        ["promotions_coupon_name"] = t.promotions_coupon_name,
        ["promotions_coupon_bonus"] = t.promotions_coupon_bonus,
        ["promotions_coupon_redeem_total_limit"] = t.promotions_coupon_redeem_total_limit,
        ["promotions_coupon_redeem_user_limit"] = t.promotions_coupon_redeem_user_limit,
        ["promotions_redeem_code_limit"] = t.promotions_redeem_code_limit,
        ["discount"] = t.discount,
        ["promotions_discounted_items"] = t.promotions_discounted_items,
        ["attribute_conditions"] = t.attribute_conditions,
        ["price_conditions_promocode"] = t.price_conditions_promocode,
        ["item_price_conditions_promocode"] = t.item_price_conditions_promocode,
        ["excluded_promotions"] = t.excluded_promotions,
    })
end


--- Create promotions_promocode_update data structure
-- @param t Table with properties. Acceptable table keys:
--   * promotions_coupon_date_start - [string] Date when your promotion will be started.
--   * promotions_coupon_date_end - [string] Date when your promotion will be finished. Can be `null`.  If `date_end` is `null`, promotion will be unlimited by time.
--   * promotions_coupon_name - [object] Name of promotion. Should contain key/value pairs
-- where key is a locale with "^[a-z]{2}-[A-Z]{2}$" format, value is string.
--   * promotions_coupon_bonus - [array] 
--   * promotions_coupon_redeem_total_limit - [integer] Limits total numbers of coupons.
--   * promotions_coupon_redeem_user_limit - [integer] Limits total numbers of coupons redeemed by single user.
--   * promotions_redeem_code_limit - [integer] Number of redemptions per code.
--   * discount - [object] 
--   * promotions_discounted_items - [array] List of items that are discounted by a promo code.
--   * attribute_conditions - [oneof] Conditions which are compared to user attribute values.
-- All conditions must be met for the action to take an effect.
--   * price_conditions_promocode - [array] Array of objects with conditions that set the price range for applying the promotion to the entire cart.
-- 
-- The total price of all items in the user's cart is compared with the price range specified in the condition. [Bonuses](/api/igs/operation/create-promo-code/#!path=bonus&t=request) and [discounts](/api/igs/operation/create-promo-code/#!path=discount&t=request) are applied to all items in the cart if the price of the cart meets the specified condition.
-- 
-- If you pass this array, set the value of the [discounted_items](/api/igs/operation/create-promo-code/#!path=discounted_items&t=request) array to `null`.
--   * item_price_conditions_promocode - [array] Array of objects with conditions that set the price range for applying the promotion to certain items in the cart.
-- 
-- The price of each item in the user's cart is compared with the price range specified in the condition. [Bonuses](/api/igs/operation/create-promo-code/#!path=bonus&t=request) and [discounts](/api/igs/operation/create-promo-code/#!path=discount&t=request) are applied only to those items in the cart whose price meets the condition.
-- 
-- If you pass this array, set the value of the [discounted_items](/api/igs/operation/create-promo-code/#!path=discounted_items&t=request) array to `null`.
--   * excluded_promotions - [array] List of promotion IDs to exclude when applying this promotion. 
-- Example: `[12, 789]`
-- @example

function M.body_promotions_promocode_update(t)
    assert(t)
    assert(t.external_id)
    assert(t.name)
    return json.encode({
        ["promotions_coupon_date_start"] = t.promotions_coupon_date_start,
        ["promotions_coupon_date_end"] = t.promotions_coupon_date_end,
        ["promotions_coupon_name"] = t.promotions_coupon_name,
        ["promotions_coupon_bonus"] = t.promotions_coupon_bonus,
        ["promotions_coupon_redeem_total_limit"] = t.promotions_coupon_redeem_total_limit,
        ["promotions_coupon_redeem_user_limit"] = t.promotions_coupon_redeem_user_limit,
        ["promotions_redeem_code_limit"] = t.promotions_redeem_code_limit,
        ["discount"] = t.discount,
        ["promotions_discounted_items"] = t.promotions_discounted_items,
        ["attribute_conditions"] = t.attribute_conditions,
        ["price_conditions_promocode"] = t.price_conditions_promocode,
        ["item_price_conditions_promocode"] = t.item_price_conditions_promocode,
        ["excluded_promotions"] = t.excluded_promotions,
    })
end


--- Create promotions_create_update_item_promotion data structure
-- @param t Table with properties. Acceptable table keys:
--   * name - [object] Name of promotion. Should contain key/value pairs,
-- where key is locale with format "^[a-z]{2}-[A-Z]{2}$", value is string.
--   * date_start - [string] Date when your promotion will be started.
--   * date_end - [string] Date when your promotion will be finished. Can be `null`.
--   * discount - [object] Object with promotion data.
--   * items - [array] Object with promotion data.
--   * attribute_conditions - [oneof] Object with promotion data.
--   * price_conditions_discount - [array] Array of objects with conditions that set the price range for applying the promotion.
--  The promotion applies only to items whose price meets all the conditions in the array. If you pass this array, set the value of the [items](/api/igs/operation/create-item-promotion/#!path=items&t=request) object to `null`.
--   * promotions_promotion_limits - [object] Promotion limits.
--   * excluded_promotions - [array] List of promotion IDs to exclude when applying this promotion. 
-- Example: `[12, 789]`
-- @example

function M.body_promotions_create_update_item_promotion(t)
    assert(t)
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
        ["price_conditions_discount"] = t.price_conditions_discount,
        ["promotions_promotion_limits"] = t.promotions_promotion_limits,
        ["excluded_promotions"] = t.excluded_promotions,
    })
end


--- Create promotions_create_update_bonus_promotion data structure
-- @param t Table with properties. Acceptable table keys:
--   * id - [integer] Promotion ID. Unique promotion identifier within the project.
--   * date_start - [string] Date when your promotion will be started.
--   * date_end - [string] Date when your promotion will be finished. Can be `null`. If `date_end` is `null`, promotion will be unlimited by time.
--   * name - [object] Name of promotion. Should contain key/value pairs where key is a locale with "^[a-z]{2}-[A-Z]{2}$" format, value is string.
--   * condition - [array] Set of items required to be included in the purchase for applying a promotion. If this parameters is `null`, a promotion will be applied to any purchases within a project.
--   * attribute_conditions - [oneof] 
--   * bonus - [array] 
--   * promotions_promotion_limits - [object] Promotion limits.
--   * price_conditions_bonus - [array] Array of objects with conditions that set the price range for applying the promotion.
--  The promotion applies only to items whose price meets all the conditions in the array. If you pass this array, set the value of the [condition](/api/igs/operation/create-bonus-promotion/#!path=condition&t=request) object to `null`.
--   * excluded_promotions - [array] List of promotion IDs to exclude when applying this promotion. 
-- Example: `[12, 789]`
-- @example

function M.body_promotions_create_update_bonus_promotion(t)
    assert(t)
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
        ["promotions_promotion_limits"] = t.promotions_promotion_limits,
        ["price_conditions_bonus"] = t.price_conditions_bonus,
        ["excluded_promotions"] = t.excluded_promotions,
    })
end


--- Create virtual_items_currency_admin_create_virtual_item data structure
-- @param t Table with properties. Acceptable table keys:
--   * virtual_items_currency_sku - [string] Unique item ID. The SKU may only contain lowercase Latin alphanumeric characters, periods, dashes, and underscores.
--   * virtual_items_currency_admin_name_two_letter_locale - [object] Object with localizations for item's name. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * virtual_items_currency_admin_description_two_letter_locale - [object] Object with localizations for item's description. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * virtual_items_currency_admin_long_description_two_letter_locale - [object] Object with localizations for long description of item. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * virtual_items_currency_schemas_admin_image_url - [string] Image URL.
--   * virtual_items_currency_admin_media_list - [array] Item's additional assets such as screenshots, gameplay video and so on.
--   * virtual_items_currency_admin_groups_create - [array] Groups the item belongs to.
-- Note. The string value refers to group `external_id`.
--   * virtual_items_currency_admin_post_put_attributes - [array] List of attributes.
-- Attention. You can't specify more than 20 attributes for the item. Any attempts to exceed the limit result in an error.
--   * virtual_items_admin_prices - [array] 
--   * virtual_items_currency_admin_create_vc_prices - [array] 
--   * virtual_items_currency_is_enabled - [boolean] 
--   * virtual_items_currency_is_deleted - [boolean] 
--   * virtual_items_currency_is_show_in_store - [boolean] 
--   * value_is_free - [boolean] If `true`, the item is free.
--   * virtual_items_currency_order - [integer] Defines arrangement order.
--   * virtual_items_currency_inventory_options - [object] Defines the inventory item options.
--   * virtual_items_currency_admin_pre_order - [object] 
--   * virtual_items_currency_admin_regions - [array] 
--   * item_limit - [object] Item limits.
--   * item_periods - [array] Item sales period.
--   * item_custom_attributes - [object] A JSON object containing item attributes and values. Attributes allow you to add more info to items like the player's required level to use the item. Attributes enrich your game's internal logic and are accessible through dedicated GET methods and webhooks.
-- @example
-- {
--   sku = "com.xsolla.sword_1",
--   name = 
--   {
--     en = "Sword",
--     de = "Schwert",
--   },
--   is_enabled = true,
--   is_free = false,
--   groups = 
--   {
--     "weapons",
--   },
--   order = 1,
--   description = 
--   {
--     en = "A sword is a bladed melee weapon intended for cutting or thrusting that is longer than a knife or dagger, consisting of a long blade attached to a hilt.",
--     de = "Ein Schwert ist eine Nahkampfwaffe mit Klinge, die zum Schneiden oder Stechen bestimmt ist, länger als ein Messer oder Dolch ist und aus einer langen Klinge besteht, die an einem Griff befestigt ist.",
--   },
--   prices = 
--   {
--     {
--       amount = 100,
--       currency = "USD",
--       is_enabled = true,
--       is_default = true,
--     },
--     {
--       amount = 200,
--       currency = "CZK",
--       country_iso = "CZ",
--       is_enabled = false,
--       is_default = true,
--     },
--   },
--   vc_prices = 
--   {
--   },
--   is_show_in_store = true,
--   attributes = 
--   {
--     {
--       external_id = "craft-materials",
--       name = 
--       {
--         en = "Craft materials",
--       },
--       values = 
--       {
--         {
--           external_id = "steel",
--           value = 
--           {
--             en-US = "5",
--           },
--         },
--         {
--           external_id = "leather",
--           value = 
--           {
--             en-US = "1",
--           },
--         },
--       },
--     },
--   },
--   limits = 
--   {
--     per_user = 5,
--     per_item = 100,
--   },
--   periods = 
--   {
--     {
--       date_from = "2020-08-11T10:00:00+03:00",
--       date_until = "2020-08-11T20:00:00+03:00",
--     },
--   },
--   custom_attributes = 
--   {
--     purchased = 0,
--     attr = "value",
--   },
-- }

function M.body_virtual_items_currency_admin_create_virtual_item(t)
    assert(t)
    return json.encode({
        ["virtual_items_currency_sku"] = t.virtual_items_currency_sku,
        ["virtual_items_currency_admin_name_two_letter_locale"] = t.virtual_items_currency_admin_name_two_letter_locale,
        ["virtual_items_currency_admin_description_two_letter_locale"] = t.virtual_items_currency_admin_description_two_letter_locale,
        ["virtual_items_currency_admin_long_description_two_letter_locale"] = t.virtual_items_currency_admin_long_description_two_letter_locale,
        ["virtual_items_currency_schemas_admin_image_url"] = t.virtual_items_currency_schemas_admin_image_url,
        ["virtual_items_currency_admin_media_list"] = t.virtual_items_currency_admin_media_list,
        ["virtual_items_currency_admin_groups_create"] = t.virtual_items_currency_admin_groups_create,
        ["virtual_items_currency_admin_post_put_attributes"] = t.virtual_items_currency_admin_post_put_attributes,
        ["virtual_items_admin_prices"] = t.virtual_items_admin_prices,
        ["virtual_items_currency_admin_create_vc_prices"] = t.virtual_items_currency_admin_create_vc_prices,
        ["virtual_items_currency_is_enabled"] = t.virtual_items_currency_is_enabled,
        ["virtual_items_currency_is_deleted"] = t.virtual_items_currency_is_deleted,
        ["virtual_items_currency_is_show_in_store"] = t.virtual_items_currency_is_show_in_store,
        ["value_is_free"] = t.value_is_free,
        ["virtual_items_currency_order"] = t.virtual_items_currency_order,
        ["virtual_items_currency_inventory_options"] = t.virtual_items_currency_inventory_options,
        ["virtual_items_currency_admin_pre_order"] = t.virtual_items_currency_admin_pre_order,
        ["virtual_items_currency_admin_regions"] = t.virtual_items_currency_admin_regions,
        ["item_limit"] = t.item_limit,
        ["item_periods"] = t.item_periods,
        ["item_custom_attributes"] = t.item_custom_attributes,
    })
end


--- Create virtual_items_currency_admin_create_virtual_currency data structure
-- @param t Table with properties. Acceptable table keys:
--   * virtual_items_currency_sku - [string] Unique item ID. The SKU may only contain lowercase Latin alphanumeric characters, periods, dashes, and underscores.
--   * virtual_items_currency_admin_name_two_letter_locale - [object] Object with localizations for item's name. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * virtual_items_currency_admin_description_two_letter_locale - [object] Object with localizations for item's description. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * virtual_items_currency_admin_long_description_two_letter_locale - [object] Object with localizations for long description of item. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * virtual_items_currency_admin_image_url - [string] 
--   * virtual_items_currency_admin_media_list - [array] Item's additional assets such as screenshots, gameplay video and so on.
--   * virtual_items_currency_admin_groups_response - [array] Groups the item belongs to.
--   * virtual_items_currency_admin_post_put_attributes - [array] List of attributes.
-- Attention. You can't specify more than 20 attributes for the item. Any attempts to exceed the limit result in an error.
--   * virtual_items_currency_admin_prices - [array] 
--   * virtual_items_currency_admin_create_vc_prices - [array] 
--   * virtual_items_currency_is_enabled - [boolean] 
--   * virtual_items_currency_is_deleted - [boolean] 
--   * virtual_items_currency_is_show_in_store - [boolean] 
--   * value_is_free - [boolean] If `true`, the item is free.
--   * virtual_items_currency_is_hard - [boolean] 
--   * virtual_items_currency_order - [integer] Defines arrangement order.
--   * virtual_items_currency_admin_pre_order - [object] 
--   * virtual_items_currency_admin_regions - [array] 
--   * item_limit - [object] Item limits.
--   * item_periods - [array] Item sales period.
--   * item_custom_attributes - [object] A JSON object containing item attributes and values. Attributes allow you to add more info to items like the player's required level to use the item. Attributes enrich your game's internal logic and are accessible through dedicated GET methods and webhooks.
-- @example
-- {
--   sku = "com.xsolla.coin_1",
--   name = 
--   {
--     en-US = "Gold coin",
--     de-DE = "Goldmünze",
--   },
--   is_enabled = true,
--   is_free = false,
--   groups = 
--   {
--     "gold",
--   },
--   order = 1,
--   description = 
--   {
--     en-US = "The main currency of your kingdom",
--     de-DE = "Die Hauptwährung deines Königreichs",
--   },
--   prices = 
--   {
--     {
--       amount = 100,
--       currency = "USD",
--       is_enabled = true,
--       is_default = true,
--     },
--   },
--   attributes = 
--   {
--     {
--       external_id = "material",
--       name = 
--       {
--         en-US = "Material",
--       },
--       values = 
--       {
--         {
--           external_id = "gold",
--           value = 
--           {
--             en-US = "Gold",
--           },
--         },
--       },
--     },
--   },
--   limits = 
--   {
--     per_user = 5,
--     per_item = 10000,
--   },
--   periods = 
--   {
--     {
--       date_from = "2020-08-11T10:00:00+03:00",
--       date_until = "2020-08-11T20:00:00+03:00",
--     },
--   },
--   custom_attributes = 
--   {
--     purchased = 0,
--     attr = "value",
--   },
-- }

function M.body_virtual_items_currency_admin_create_virtual_currency(t)
    assert(t)
    assert(t.sku)
    assert(t.name)
    return json.encode({
        ["virtual_items_currency_sku"] = t.virtual_items_currency_sku,
        ["virtual_items_currency_admin_name_two_letter_locale"] = t.virtual_items_currency_admin_name_two_letter_locale,
        ["virtual_items_currency_admin_description_two_letter_locale"] = t.virtual_items_currency_admin_description_two_letter_locale,
        ["virtual_items_currency_admin_long_description_two_letter_locale"] = t.virtual_items_currency_admin_long_description_two_letter_locale,
        ["virtual_items_currency_admin_image_url"] = t.virtual_items_currency_admin_image_url,
        ["virtual_items_currency_admin_media_list"] = t.virtual_items_currency_admin_media_list,
        ["virtual_items_currency_admin_groups_response"] = t.virtual_items_currency_admin_groups_response,
        ["virtual_items_currency_admin_post_put_attributes"] = t.virtual_items_currency_admin_post_put_attributes,
        ["virtual_items_currency_admin_prices"] = t.virtual_items_currency_admin_prices,
        ["virtual_items_currency_admin_create_vc_prices"] = t.virtual_items_currency_admin_create_vc_prices,
        ["virtual_items_currency_is_enabled"] = t.virtual_items_currency_is_enabled,
        ["virtual_items_currency_is_deleted"] = t.virtual_items_currency_is_deleted,
        ["virtual_items_currency_is_show_in_store"] = t.virtual_items_currency_is_show_in_store,
        ["value_is_free"] = t.value_is_free,
        ["virtual_items_currency_is_hard"] = t.virtual_items_currency_is_hard,
        ["virtual_items_currency_order"] = t.virtual_items_currency_order,
        ["virtual_items_currency_admin_pre_order"] = t.virtual_items_currency_admin_pre_order,
        ["virtual_items_currency_admin_regions"] = t.virtual_items_currency_admin_regions,
        ["item_limit"] = t.item_limit,
        ["item_periods"] = t.item_periods,
        ["item_custom_attributes"] = t.item_custom_attributes,
    })
end


--- Create virtual_items_currency_admin_create_virtual_currency_package data structure
-- @param t Table with properties. Acceptable table keys:
--   * virtual_items_currency_sku - [string] Unique item ID. The SKU may only contain lowercase Latin alphanumeric characters, periods, dashes, and underscores.
--   * virtual_items_currency_admin_name_two_letter_locale - [object] Object with localizations for item's name. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * virtual_items_currency_admin_description_two_letter_locale - [object] Object with localizations for item's description. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * virtual_items_currency_admin_long_description_two_letter_locale - [object] Object with localizations for long description of item. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * virtual_items_currency_admin_image_url - [string] 
--   * virtual_items_currency_admin_media_list - [array] Item's additional assets such as screenshots, gameplay video and so on.
--   * virtual_items_currency_admin_groups_create - [array] Groups the item belongs to.
-- Note. The string value refers to group `external_id`.
--   * virtual_items_currency_admin_post_put_attributes - [array] List of attributes.
-- Attention. You can't specify more than 20 attributes for the item. Any attempts to exceed the limit result in an error.
--   * virtual_items_currency_admin_prices - [array] 
--   * virtual_items_currency_admin_create_vc_prices - [array] 
--   * virtual_items_currency_is_enabled - [boolean] 
--   * virtual_items_currency_is_deleted - [boolean] 
--   * virtual_items_currency_is_show_in_store - [boolean] 
--   * value_is_free - [boolean] If `true`, the item is free.
--   * virtual_items_currency_order - [integer] Defines arrangement order.
--   * content - [array] Virtual currency package should contain only 1 position of virtual currency.
--   * virtual_items_currency_admin_pre_order - [object] 
--   * virtual_items_currency_admin_regions - [array] 
--   * item_limit - [object] Item limits.
--   * item_periods - [array] Item sales period.
--   * item_custom_attributes - [object] A JSON object containing item attributes and values. Attributes allow you to add more info to items like the player's required level to use the item. Attributes enrich your game's internal logic and are accessible through dedicated GET methods and webhooks.
-- @example
-- {
--   sku = "com.xsolla.novigrad_crown_500",
--   name = 
--   {
--     en-US = "500x Novigradian crown",
--     ru-RU = "500x Новиградских крон",
--   },
--   is_enabled = true,
--   is_free = false,
--   groups = 
--   {
--     "witcher",
--   },
--   order = 1,
--   long_description = 
--   {
--     en-US = "Long Test new",
--     ru-RU = "Длинное описание",
--   },
--   description = 
--   {
--     en-US = "The Crown (also known as the Novigradian crown) is a monetary unit which is used in some Northern Kingdoms",
--     ru-RU = "Крона (Также известна как Новиградская крона) - платежная единица, используемая в северных королевствах",
--   },
--   image_url = "https://vignette.wikia.nocookie.net/witcher/images/7/7c/Items_Orens.png/revision/latest?cb=20081113120917",
--   media_list = 
--   {
--     {
--       type = "image",
--       url = "https://test.com/image0",
--     },
--     {
--       type = "image",
--       url = "https://test.com/image1",
--     },
--   },
--   attributes = 
--   {
--     {
--       external_id = "event",
--       name = 
--       {
--         en-US = "Event",
--       },
--       values = 
--       {
--         {
--           external_id = "10-anniversary",
--           value = 
--           {
--             en-US = "10th anniversary",
--           },
--         },
--         {
--           external_id = "christmas",
--           value = 
--           {
--             en-US = "Christmas",
--           },
--         },
--       },
--     },
--   },
--   prices = 
--   {
--     {
--       currency = "USD",
--       amount = 99.99,
--       is_default = true,
--     },
--     {
--       currency = "EUR",
--       amount = 80.03,
--       is_enabled = false,
--     },
--   },
--   vc_prices = nil,
--   content = 
--   {
--     {
--       sku = "com.xsolla.novigrad_crown",
--       quantity = 500,
--     },
--   },
--   limits = 
--   {
--     per_user = nil,
--     per_item = nil,
--   },
--   periods = 
--   {
--     {
--       date_from = "2020-08-11T10:00:00+03:00",
--       date_until = "2020-08-11T20:00:00+03:00",
--     },
--   },
--   custom_attributes = 
--   {
--     purchased = 0,
--     attr = "value",
--   },
-- }

function M.body_virtual_items_currency_admin_create_virtual_currency_package(t)
    assert(t)
    assert(t.sku)
    assert(t.name)
    assert(t.description)
    assert(t.content)
    return json.encode({
        ["virtual_items_currency_sku"] = t.virtual_items_currency_sku,
        ["virtual_items_currency_admin_name_two_letter_locale"] = t.virtual_items_currency_admin_name_two_letter_locale,
        ["virtual_items_currency_admin_description_two_letter_locale"] = t.virtual_items_currency_admin_description_two_letter_locale,
        ["virtual_items_currency_admin_long_description_two_letter_locale"] = t.virtual_items_currency_admin_long_description_two_letter_locale,
        ["virtual_items_currency_admin_image_url"] = t.virtual_items_currency_admin_image_url,
        ["virtual_items_currency_admin_media_list"] = t.virtual_items_currency_admin_media_list,
        ["virtual_items_currency_admin_groups_create"] = t.virtual_items_currency_admin_groups_create,
        ["virtual_items_currency_admin_post_put_attributes"] = t.virtual_items_currency_admin_post_put_attributes,
        ["virtual_items_currency_admin_prices"] = t.virtual_items_currency_admin_prices,
        ["virtual_items_currency_admin_create_vc_prices"] = t.virtual_items_currency_admin_create_vc_prices,
        ["virtual_items_currency_is_enabled"] = t.virtual_items_currency_is_enabled,
        ["virtual_items_currency_is_deleted"] = t.virtual_items_currency_is_deleted,
        ["virtual_items_currency_is_show_in_store"] = t.virtual_items_currency_is_show_in_store,
        ["value_is_free"] = t.value_is_free,
        ["virtual_items_currency_order"] = t.virtual_items_currency_order,
        ["content"] = t.content,
        ["virtual_items_currency_admin_pre_order"] = t.virtual_items_currency_admin_pre_order,
        ["virtual_items_currency_admin_regions"] = t.virtual_items_currency_admin_regions,
        ["item_limit"] = t.item_limit,
        ["item_periods"] = t.item_periods,
        ["item_custom_attributes"] = t.item_custom_attributes,
    })
end


--- Create create_update_region data structure
-- @param t Table with properties. Acceptable table keys:
--   * regions_countries - [array] List of countries to be added in a region.
-- 
-- Two-letter uppercase country code per [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2).
-- Check the documentation for detailed information about [countries supported by Xsolla](https://developers.xsolla.com/doc/in-game-store/references/supported-countries/).
-- 
-- Example: `["JP", "CN", "VN"]`
--   * regions_name - [object] Name of region. Should contain key/value pairs where key is a locale with the "^[a-z]{2}-[A-Z]{2}$" format, the value is string.
-- @example

function M.body_create_update_region(t)
    assert(t)
    assert(t.countries)
    assert(t.name)
    return json.encode({
        ["regions_countries"] = t.regions_countries,
        ["regions_name"] = t.regions_name,
    })
end


--- Create reset_user_limits data structure
-- @param t Table with properties. Acceptable table keys:
--   * user_limit_user - [object] 
-- @example
-- {
--   user = 
--   {
--     user_external_id = "d342dad2-9d59-11e9-a384-42010aa8003f",
--   },
-- }

function M.body_reset_user_limits(t)
    assert(t)
    assert(t.user)
    return json.encode({
        ["user_limit_user"] = t.user_limit_user,
    })
end


--- Create reset_user_limits_flexible data structure
-- @param t Table with properties. Acceptable table keys:
--   * user_limit_user_flexible - [object] 
-- @example
-- {
--   user = 
--   {
--     user_external_id = "d342dad2-9d59-11e9-a384-42010aa8003f",
--   },
-- }

function M.body_reset_user_limits_flexible(t)
    assert(t)
    assert(t.user)
    return json.encode({
        ["user_limit_user_flexible"] = t.user_limit_user_flexible,
    })
end


--- Create update_user_limits_flexible data structure
-- @param t Table with properties. Acceptable table keys:
--   * user_limit_user - [object] 
--   * user_limit_available_flexible - [integer] Remaining number of items or promotion uses available to the user within the limit applied.
-- @example
-- {
--   user = 
--   {
--     user_external_id = "d342dad2-9d59-11e9-a384-42010aa8003f",
--   },
--   available = 0,
-- }

function M.body_update_user_limits_flexible(t)
    assert(t)
    assert(t.user)
    assert(t.available)
    return json.encode({
        ["user_limit_user"] = t.user_limit_user,
        ["user_limit_available_flexible"] = t.user_limit_available_flexible,
    })
end


--- Create update_user_limits_strict data structure
-- @param t Table with properties. Acceptable table keys:
--   * user_limit_user - [object] 
--   * user_limit_available - [integer] Remaining number of items or promotion uses available to the user within the limit applied.
-- @example
-- {
--   user = 
--   {
--     user_external_id = "d342dad2-9d59-11e9-a384-42010aa8003f",
--   },
--   available = 1,
-- }

function M.body_update_user_limits_strict(t)
    assert(t)
    assert(t.user)
    assert(t.available)
    return json.encode({
        ["user_limit_user"] = t.user_limit_user,
        ["user_limit_available"] = t.user_limit_available,
    })
end


--- Create update_promo_code_user_limits_flexible data structure
-- @param t Table with properties. Acceptable table keys:
--   * user_limit_user - [object] 
--   * promo_code_user_limit_available_flexible - [integer] Remaining number of the promo code uses available to the user within the limit applied.
-- @example
-- {
--   user = 
--   {
--     user_external_id = "d342dad2-9d59-11e9-a384-42010aa8003f",
--   },
--   available = 0,
-- }

function M.body_update_promo_code_user_limits_flexible(t)
    assert(t)
    assert(t.user)
    assert(t.available)
    return json.encode({
        ["user_limit_user"] = t.user_limit_user,
        ["promo_code_user_limit_available_flexible"] = t.promo_code_user_limit_available_flexible,
    })
end


--- Create update_promo_code_user_limits_strict data structure
-- @param t Table with properties. Acceptable table keys:
--   * user_limit_user - [object] 
--   * promo_code_user_limit_available - [integer] Remaining number of the promo code uses available to the user within the limit applied.
-- @example
-- {
--   user = 
--   {
--     user_external_id = "d342dad2-9d59-11e9-a384-42010aa8003f",
--   },
--   available = 1,
-- }

function M.body_update_promo_code_user_limits_strict(t)
    assert(t)
    assert(t.user)
    assert(t.available)
    return json.encode({
        ["user_limit_user"] = t.user_limit_user,
        ["promo_code_user_limit_available"] = t.promo_code_user_limit_available,
    })
end


--- Create update_coupon_user_limits_flexible data structure
-- @param t Table with properties. Acceptable table keys:
--   * user_limit_user - [object] 
--   * coupon_user_limit_available_flexible - [integer] Remaining number of the coupon uses available to the user within the limit applied.
-- @example
-- {
--   user = 
--   {
--     user_external_id = "d342dad2-9d59-11e9-a384-42010aa8003f",
--   },
--   available = 0,
-- }

function M.body_update_coupon_user_limits_flexible(t)
    assert(t)
    assert(t.user)
    assert(t.available)
    return json.encode({
        ["user_limit_user"] = t.user_limit_user,
        ["coupon_user_limit_available_flexible"] = t.coupon_user_limit_available_flexible,
    })
end


--- Create update_coupon_user_limits_strict data structure
-- @param t Table with properties. Acceptable table keys:
--   * user_limit_user - [object] 
--   * coupon_user_limit_available - [integer] Remaining number of the coupon uses available to the user within the limit applied.
-- @example
-- {
--   user = 
--   {
--     user_external_id = "d342dad2-9d59-11e9-a384-42010aa8003f",
--   },
--   available = 1,
-- }

function M.body_update_coupon_user_limits_strict(t)
    assert(t)
    assert(t.user)
    assert(t.available)
    return json.encode({
        ["user_limit_user"] = t.user_limit_user,
        ["coupon_user_limit_available"] = t.coupon_user_limit_available,
    })
end


--- Create create_value_point data structure
-- @param t Table with properties. Acceptable table keys:
--   * description_two_letter_locale - [object] Object with localizations for item's description. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * common_admin_image_url - [string] Image URL.
--   * is_enabled - [boolean] 
--   * long_description_two_letter_locale - [object] Object with localizations for long description of item. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * media_list - [array] Item's additional assets such as screenshots, gameplay video and so on.
--   * name_two_letter_locale - [object] Object with localizations for item's name. Two-letter lowercase [language code](https://developers.xsolla.com/doc/pay-station/features/localization/).
--   * order - [integer] Defines arrangement order.
--   * sku - [string] Unique item ID. The SKU may only contain lowercase Latin alphanumeric characters, periods, dashes, and underscores.
--   * is_clan - [boolean] Whether the value point is used in clan reward chains.
-- @example

function M.body_create_value_point(t)
    assert(t)
    assert(t.sku)
    assert(t.name)
    return json.encode({
        ["description_two_letter_locale"] = t.description_two_letter_locale,
        ["common_admin_image_url"] = t.common_admin_image_url,
        ["is_enabled"] = t.is_enabled,
        ["long_description_two_letter_locale"] = t.long_description_two_letter_locale,
        ["media_list"] = t.media_list,
        ["name_two_letter_locale"] = t.name_two_letter_locale,
        ["order"] = t.order,
        ["sku"] = t.sku,
        ["is_clan"] = t.is_clan,
    })
end


--- Create set_item_value_point_reward data structure
-- @param t Table with properties. Acceptable table keys:
-- @example
-- {
--   {
--     sku = "com.xsolla.booster_1",
--     amount = 100,
--   },
--   {
--     sku = "com.xsolla.booster_mega",
--     amount = 200,
--   },
-- }

function M.body_set_item_value_point_reward(t)
    assert(t)
    return json.encode({
    })
end


--- Create set_item_value_point_reward_for_patch data structure
-- @param t Table with properties. Acceptable table keys:
-- @example
-- {
--   {
--     sku = "booster_1",
--     amount = 100,
--   },
--   {
--     sku = "booster_mega",
--     amount = 0,
--   },
-- }

function M.body_set_item_value_point_reward_for_patch(t)
    assert(t)
    return json.encode({
    })
end


--- Create create_reward_chain data structure
-- @param t Table with properties.
-- @example

function M.body_create_reward_chain(t)
    assert(t)
    return json.encode(t)
end


--- Create update_reward_chain data structure
-- @param t Table with properties.
-- @example

function M.body_update_reward_chain(t)
    assert(t)
    return json.encode(t)
end


--- Create promotions_unique_catalog_offer_create data structure
-- @param t Table with properties. Acceptable table keys:
--   * promotions_coupon_external_id - [string] Unique promotion ID. The `external_id` may only contain lowercase Latin alphanumeric characters, periods, dashes, and underscores.
--   * promotions_coupon_date_start - [string] Date when your promotion will be started.
--   * promotions_coupon_date_end - [string] Date when your promotion will be finished. Can be `null`.  If `date_end` is `null`, promotion will be unlimited by time.
--   * promotions_coupon_name - [object] Name of promotion. Should contain key/value pairs
-- where key is a locale with "^[a-z]{2}-[A-Z]{2}$" format, value is string.
--   * promotions_unique_catalog_offer_items - [array] A list of items SKU that are available after using the unique catalog offer.
--   * promotions_coupon_redeem_user_limit - [integer] Limits total numbers of coupons redeemed by single user.
--   * promotions_redeem_code_limit - [integer] Number of redemptions per code.
--   * promotions_coupon_redeem_total_limit - [integer] Limits total numbers of coupons.
-- @example

function M.body_promotions_unique_catalog_offer_create(t)
    assert(t)
    assert(t.external_id)
    assert(t.name)
    return json.encode({
        ["promotions_coupon_external_id"] = t.promotions_coupon_external_id,
        ["promotions_coupon_date_start"] = t.promotions_coupon_date_start,
        ["promotions_coupon_date_end"] = t.promotions_coupon_date_end,
        ["promotions_coupon_name"] = t.promotions_coupon_name,
        ["promotions_unique_catalog_offer_items"] = t.promotions_unique_catalog_offer_items,
        ["promotions_coupon_redeem_user_limit"] = t.promotions_coupon_redeem_user_limit,
        ["promotions_redeem_code_limit"] = t.promotions_redeem_code_limit,
        ["promotions_coupon_redeem_total_limit"] = t.promotions_coupon_redeem_total_limit,
    })
end


--- Create promotions_unique_catalog_offer_update data structure
-- @param t Table with properties. Acceptable table keys:
--   * promotions_coupon_date_start - [string] Date when your promotion will be started.
--   * promotions_coupon_date_end - [string] Date when your promotion will be finished. Can be `null`.  If `date_end` is `null`, promotion will be unlimited by time.
--   * promotions_coupon_name - [object] Name of promotion. Should contain key/value pairs
-- where key is a locale with "^[a-z]{2}-[A-Z]{2}$" format, value is string.
--   * promotions_unique_catalog_offer_items - [array] A list of items SKU that are available after using the unique catalog offer.
--   * promotions_coupon_redeem_total_limit - [integer] Limits total numbers of coupons.
--   * promotions_coupon_redeem_user_limit - [integer] Limits total numbers of coupons redeemed by single user.
--   * promotions_redeem_code_limit - [integer] Number of redemptions per code.
-- @example

function M.body_promotions_unique_catalog_offer_update(t)
    assert(t)
    assert(t.name)
    return json.encode({
        ["promotions_coupon_date_start"] = t.promotions_coupon_date_start,
        ["promotions_coupon_date_end"] = t.promotions_coupon_date_end,
        ["promotions_coupon_name"] = t.promotions_coupon_name,
        ["promotions_unique_catalog_offer_items"] = t.promotions_unique_catalog_offer_items,
        ["promotions_coupon_redeem_total_limit"] = t.promotions_coupon_redeem_total_limit,
        ["promotions_coupon_redeem_user_limit"] = t.promotions_coupon_redeem_user_limit,
        ["promotions_redeem_code_limit"] = t.promotions_redeem_code_limit,
    })
end


--- Create connector_import_items_body data structure
-- @param t Table with properties. Acceptable table keys:
--   * connector_external_id - [string] A fixed value that specifies the type of operation for importing items.
--   * file_url - [string] The URL of a file with data in JSON format. The file should be hosted on a storage service with public access. You can download the file template in Publisher Account in the [Store > Virtual Items > Catalog Management > Import Items (JSON)](https://publisher.xsolla.com/0/projects/0/storefront/import-export/import-items) section.
--   * mode - [string] Import actions:
-- @example

function M.body_connector_import_items_body(t)
    assert(t)
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create attribute
-- Creates an attribute.
-- /v2/project/{project_id}/admin/attribute
-- @name admin_create_attribute
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_create_update_attribute()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_attribute(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/attribute"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update attribute
-- Updates an attribute.
-- /v2/project/{project_id}/admin/attribute/{external_id}
-- @name admin_update_attribute
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Attribute external ID.
-- @param body Create using body_create_update_attribute()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_attribute(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/attribute/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_create_update_attribute_value()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_attribute_value(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/attribute/{external_id}/value"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update attribute value
-- Updates an attribute values.
-- /v2/project/{project_id}/admin/attribute/{external_id}/value/{value_external_id}
-- @name admin_update_attribute_value
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param value_external_id (REQUIRED) Attribute value external ID.
-- @param external_id (REQUIRED) Attribute external ID.
-- @param body Create using body_create_update_attribute_value()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_attribute_value(project_id, value_external_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(value_external_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/attribute/{external_id}/value/{value_external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{value_external_id}", uri.encode(tostring(value_external_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{value_external_id}", uri.encode(tostring(value_external_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["is_enabled"] = is_enabled

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create catalog filter rule
-- Create rule for user attributes.
-- /v2/project/{project_id}/admin/user/attribute/rule
-- @name create_filter_rule
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_personalized_catalog_create_update_body()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_filter_rule(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/user/attribute/rule"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{rule_id}", uri.encode(tostring(rule_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update catalog filter rule
-- Updates a specific rule applying to user attributes. The default value will be used for a not specified property (if property is not required).
-- /v2/project/{project_id}/admin/user/attribute/rule/{rule_id}
-- @name update_filter_rule_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param rule_id (REQUIRED) Rule ID.
-- @param body Create using body_personalized_catalog_create_update_body()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_filter_rule_by_id(project_id, rule_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(rule_id)

    local url_path = "/v2/project/{project_id}/admin/user/attribute/rule/{rule_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{rule_id}", uri.encode(tostring(rule_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Patch catalog filter rule
-- Updates a specific rule applying to user attributes. The current value will be used for a not specified property.
-- /v2/project/{project_id}/admin/user/attribute/rule/{rule_id}
-- @name patch_filter_rule_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param rule_id (REQUIRED) Rule ID.
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.patch_filter_rule_by_id(project_id, rule_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(rule_id)

    local url_path = "/v2/project/{project_id}/admin/user/attribute/rule/{rule_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{rule_id}", uri.encode(tostring(rule_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PATCH", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{rule_id}", uri.encode(tostring(rule_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create bundle
-- Creates a bundle.
-- /v2/project/{project_id}/admin/items/bundle
-- @name admin_create_bundle
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_bundles_bundle()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_bundle(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/bundle"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{group_id}", uri.encode(tostring(group_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update bundle
-- Updates a bundle.
-- /v2/project/{project_id}/admin/items/bundle/sku/{sku}
-- @name admin_update_bundle
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param sku (REQUIRED) Bundle SKU.
-- @param body Create using body_bundles_bundle()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_bundle(project_id, sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(sku)

    local url_path = "/v2/project/{project_id}/admin/items/bundle/sku/{sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{sku}", uri.encode(tostring(sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{sku}", uri.encode(tostring(sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{sku}", uri.encode(tostring(sku)))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{sku}", uri.encode(tostring(sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{sku}", uri.encode(tostring(sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{sku}", uri.encode(tostring(sku)))

    local query_params = {}
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))

    local query_params = {}
    query_params["currency"] = currency
    query_params["locale"] = locale

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get current user&#x27;s cart
-- Returns the current user&#x27;s cart.
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["currency"] = currency
    query_params["locale"] = locale

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Fill cart with items
-- Fills the cart with items. If the cart already has an item with the same SKU, the existing item will be replaced by the passed value.
-- /v2/project/{project_id}/cart/fill
-- @name cart_fill
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_cart_payment_fill_cart_json_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.cart_fill(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/cart/fill"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Fill specific cart with items
-- Fills the specific cart with items. If the cart already has an item with the same SKU, the existing item position will be replaced by the passed value.
-- /v2/project/{project_id}/cart/{cart_id}/fill
-- @name cart_fill_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param body Create using body_cart_payment_fill_cart_json_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.cart_fill_by_id(project_id, cart_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/project/{project_id}/cart/{cart_id}/fill"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update cart item by cart ID
-- Updates an existing cart item or creates the one in the cart.
-- /v2/project/{project_id}/cart/{cart_id}/item/{item_sku}
-- @name put_item_by_cart_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_cart_payment_put_item_by_cart_idjsonmodel()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
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

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update cart item from current cart
-- Updates an existing cart item or creates the one in the cart.
-- /v2/project/{project_id}/cart/item/{item_sku}
-- @name put_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_cart_payment_put_item_by_cart_idjsonmodel()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.put_item(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/cart/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
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
-- 
--  As this method uses the IP to determine the user’s country and select a currency for the order, it is important to only use this method from the client side and not from the server side. Using this method from the server side may cause incorrect currency determination and affect payment methods in Pay Station. 
-- /v2/project/{project_id}/payment/cart/{cart_id}
-- @name create_order_by_cart_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param body Create using body_cart_payment_create_order_by_cart_idjsonmodel()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_order_by_cart_id(project_id, cart_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/project/{project_id}/payment/cart/{cart_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
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
-- 
--  As this method uses the IP to determine the user’s country and select a currency for the order, it is important to only use this method from the client side and not from the server side. Using this method from the server side may cause incorrect currency determination and affect payment methods in Pay Station. 
-- /v2/project/{project_id}/payment/cart
-- @name create_order
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_cart_payment_create_order_by_cart_idjsonmodel()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_order(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/payment/cart"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
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
-- 
--  As this method uses the IP to determine the user’s country and select a currency for the order, it is important to only use this method from the client side and not from the server side. Using this method from the server side may cause incorrect currency determination and affect payment methods in Pay Station. 
-- /v2/project/{project_id}/payment/item/{item_sku}
-- @name create_order_with_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_cart_payment_create_order_with_specified_item_idjsonmodel()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_order_with_item(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/payment/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create order with free cart
-- Creates an order with all items from the free cart. The created order will get a `done` order status.
-- /v2/project/{project_id}/free/cart
-- @name create_free_order
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_cart_payment_create_order_by_cart_idjsonmodel()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_free_order(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/free/cart"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create order with particular free cart
-- Creates an order with all items from the particular free cart. The created order will get a `done` order status.
-- /v2/project/{project_id}/free/cart/{cart_id}
-- @name create_free_order_by_cart_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param cart_id (REQUIRED) Cart ID.
-- @param body Create using body_cart_payment_create_order_by_cart_idjsonmodel()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_free_order_by_cart_id(project_id, cart_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/project/{project_id}/free/cart/{cart_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create order with specified free item
-- Creates an order with a specified free item. The created order will get a `done` order status.
-- /v2/project/{project_id}/free/item/{item_sku}
-- @name create_free_order_with_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_cart_payment_create_order_with_specified_item_idjsonmodel()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_free_order_with_item(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/free/item/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{order_id}", uri.encode(tostring(order_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get orders list for specified period
-- Retrieves orders list, arranged from the earliest to the latest creation date.
-- /v3/project/{project_id}/admin/order/search
-- @name admin_order_search
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_admin_order_search()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_order_search(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v3/project/{project_id}/admin/order/search"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
--    user.country.value parameter is used to select a currency for the order. If user&#x27;s country is unknown,
-- providing the user&#x27;s IP in X-User-Ip header is an alternative option. 
--  One of these two options is required for the correct work of this method. 
--  The selected currency is used for payment methods at Pay Station.
--    
-- /v3/project/{project_id}/admin/payment/token
-- @name admin_create_payment_token
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_cart_payment_admin_create_payment_token()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_payment_token(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v3/project/{project_id}/admin/payment/token"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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

-- @param body Create using body_cart_payment_admin_fill_cart_json_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_cart_fill(project_id, locale, x_user_for, x_user_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/admin/project/{project_id}/cart/fill"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["locale"] = locale

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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

-- @param body Create using body_cart_payment_admin_fill_cart_json_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_fill_cart_by_id(project_id, cart_id, locale, x_user_for, x_user_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(cart_id)

    local url_path = "/v2/admin/project/{project_id}/cart/{cart_id}/fill"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{cart_id}", uri.encode(tostring(cart_id)))

    local query_params = {}
    query_params["locale"] = locale

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update information about webhook settings
-- Updates the information about the webhook settings in Store.
-- Check webhooks [documentation](/doc/in-game-store/integration-guide/set-up-webhooks/) to learn more.
-- /v2/project/{project_id}/admin/webhook
-- @name update_webhook
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_webhook(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/webhook"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get information about item pre-order limit
-- Get pre-order limit of the item.
-- 
-- Pre-Order limit API allows you to sell an item in a limited quantity. For configuring the pre-order itself, go to the Admin section of the desired item module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Add quantity to item pre-order limit
-- Add quantity to pre-order limit of the item.
-- 
-- Pre-Order limit API allows you to sell an item in a limited quantity. For configuring the pre-order itself, go to the Admin section of the desired item module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/pre_order/limit/item/id/{item_id}
-- /v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}
-- @name add_pre_order_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.add_pre_order_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Set quantity of item pre-order limit
-- Set quantity of pre-order limit of the item.
-- 
-- Pre-Order limit API allows you to sell an item in a limited quantity. For configuring the pre-order itself, go to the Admin section of the desired item module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/pre_order/limit/item/id/{item_id}
-- /v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}
-- @name set_pre_order_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.set_pre_order_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Remove quantity of item pre-order limit
-- Remove quantity of pre-order limit of the item.
-- 
-- Pre-Order limit API allows you to sell an item in a limited quantity. For configuring the pre-order itself, go to the Admin section of the desired item module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/pre_order/limit/item/id/{item_id}
-- /v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}
-- @name remove_pre_order_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.remove_pre_order_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Toggle item&#x27;s pre-order limit
-- Enable/disable pre-order limit of the item.
-- 
-- Pre-Order limit API allows you to sell an item in a limited quantity. For configuring the pre-order itself, go to the admin section of the desired item module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- 
-- Aliases for this endpoint:
-- * /v2/project/{project_id}/admin/items/pre_order/limit/item/id/{item_id}/toggle
-- /v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}/toggle
-- @name toggle_pre_order_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.toggle_pre_order_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/pre_order/limit/item/sku/{item_sku}/toggle"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Remove all quantity of item pre-order limit
-- Remove all quantity of pre-order limit of the item.
-- 
-- Pre-Order limit API allows you to sell an item in a limited quantity. For configuring the pre-order itself, go to the admin section of the desired item module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get information about upsell in project
-- Retrieves the information about upsell in project: whether it&#x27;s enabled, type of upsell, and the SKU list of items that are a part of this upsell.
-- /v2/project/{project_id}/admin/items/upsell
-- @name get_upsell_configurations_for_project_admin
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.get_upsell_configurations_for_project_admin(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/upsell"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create upsell
-- Creates an upsell for a project.
-- /v2/project/{project_id}/admin/items/upsell
-- @name post_upsell
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_create_upsell()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.post_upsell(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/upsell"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update upsell
-- Update an upsell for a project.
-- /v2/project/{project_id}/admin/items/upsell
-- @name put_upsell
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_update_upsell()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.put_upsell(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/upsell"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{toggle}", uri.encode(tostring(toggle)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get projects
-- Gets the list of merchant&#x27;s projects.
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
    url_path = url_path:gsub("{merchant_id}", uri.encode(tostring(merchant_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create game
-- Creates a game in the project.
-- /v2/project/{project_id}/admin/items/game
-- @name admin_create_game
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_game_keys_create_update_game_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_game(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/game"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update game by SKU
-- Updates a game in the project by SKU.
-- /v2/project/{project_id}/admin/items/game/sku/{item_sku}
-- @name admin_update_game_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_game_keys_create_update_game_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_game_by_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/game/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_id}", uri.encode(tostring(item_id)))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update game by ID
-- Updates a game in the project by ID.
-- /v2/project/{project_id}/admin/items/game/id/{item_id}
-- @name admin_update_game_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param body Create using body_game_keys_create_update_game_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_game_by_id(project_id, item_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/admin/items/game/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_id}", uri.encode(tostring(item_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_id}", uri.encode(tostring(item_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Upload codes
-- Uploads codes by game key SKU.
-- /v2/project/{project_id}/admin/items/game/key/upload/sku/{item_sku}
-- @name admin_upload_codes_by_sku
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_upload_codes_by_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/game/key/upload/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Upload codes by ID
-- Uploads codes by game key ID.
-- /v2/project/{project_id}/admin/items/game/key/upload/id/{item_id}
-- @name admin_upload_codes_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_upload_codes_by_id(project_id, item_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/admin/items/game/key/upload/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_id}", uri.encode(tostring(item_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{session_id}", uri.encode(tostring(session_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}
    query_params["user_email"] = user_email
    query_params["quantity"] = quantity
    query_params["reason"] = reason
    query_params["region_id"] = region_id

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_id}", uri.encode(tostring(item_id)))

    local query_params = {}
    query_params["user_email"] = user_email
    query_params["quantity"] = quantity
    query_params["reason"] = reason
    query_params["region_id"] = region_id

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}
    query_params["user_email"] = user_email
    query_params["reason"] = reason
    query_params["region_id"] = region_id

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_id}", uri.encode(tostring(item_id)))

    local query_params = {}
    query_params["user_email"] = user_email
    query_params["reason"] = reason
    query_params["region_id"] = region_id

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["sandbox"] = sandbox
    query_params["additional_fields"] = additional_fields

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.redeem_game_pin_code(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/entitlement/redeem"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.grant_entitlement_admin(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/entitlement/grant"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.revoke_entitlement_admin(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/entitlement/revoke"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["locale"] = locale
    query_params["additional_fields"] = additional_fields
    query_params["country"] = country

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create physical item
-- Adds a new item.
-- /v2/project/{project_id}/admin/items/physical_good
-- @name admin_create_physical_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_physical_items_create_update_physical_good_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_physical_item(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_physical_items_patch_physical_good_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_physical_item_by_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_physical_items_patch_physical_good_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_patch_physical_item_by_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PATCH", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_id}", uri.encode(tostring(item_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update physical item by ID
-- Updates a physical item by ID.
-- /v2/project/{project_id}/admin/items/physical_good/id/{item_id}
-- @name admin_update_physical_item_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param body Create using body_physical_items_create_update_physical_good_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_physical_item_by_id(project_id, item_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_id}", uri.encode(tostring(item_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Partially update physical item by ID
-- Partially updates a physical item by ID.
-- /v2/project/{project_id}/admin/items/physical_good/id/{item_id}
-- @name admin_patch_physical_item_by_id
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_id (REQUIRED) Item ID.
-- @param body Create using body_physical_items_patch_physical_good_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_patch_physical_item_by_id(project_id, item_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_id)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/id/{item_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_id}", uri.encode(tostring(item_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PATCH", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_id}", uri.encode(tostring(item_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get all delivery methods
-- This API allows to specify method of item&#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Add new delivery method
-- This API allows to specify method of item&#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
-- 
-- 
-- To use the methods, you should specify fulfilment XSOLLA_SIMPLE in project
-- delivery settings.
-- /v2/project/{project_id}/admin/items/physical_good/delivery/method
-- @name admin_create_delivery_method
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_delivery_method(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/method"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get delivery method information by method code
-- This API allows to specify method of item&#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{code}", uri.encode(tostring(code)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update delivery method information by method code
-- This API allows to specify method of item&#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
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
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_delivery_method_method_code(project_id, code, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(code)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/method/code/{code}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{code}", uri.encode(tostring(code)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Remove delivery method by method code
-- This API allows to specify method of item&#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{code}", uri.encode(tostring(code)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get item delivery prices information
-- This API allows to specify method of item&#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Add new delivery prices
-- This API allows to specify method of item&#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
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
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_add_delivery_method_price_item_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/price/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Remove delivery prices
-- This API allows to specify method of item&#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
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
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_delete_delivery_method_price_item_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/price/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Replace delivery prices
-- This API allows to specify method of item&#x27;s delivery and delivery prices in
-- different currencies. User chooses one of the provided methods after they 
-- provide shipping address information.
-- 
-- 
--   NoteTo make the delivery method available to the user, all items in user&#x27;s order should have the delivery price for this method in the currency of the order. Final shipping price is calculated by summing prices of all items for this delivery method.
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
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_replace_delivery_method_price_item_sku(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/physical_good/delivery/price/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["enabled"] = enabled

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promotion_id}", uri.encode(tostring(promotion_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promotion_id}", uri.encode(tostring(promotion_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{code}", uri.encode(tostring(code)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Redeem coupon code
-- Redeems a coupon code. The user gets a bonus after a coupon is redeemed.
-- /v2/project/{project_id}/coupon/redeem
-- @name redeem_coupon
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_promotions_redeem_coupon_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.redeem_coupon(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/coupon/redeem"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{coupon_code}", uri.encode(tostring(coupon_code)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create coupon promotion
-- Creates a coupon promotion.
-- /v2/project/{project_id}/admin/coupon
-- @name admin_create_coupon
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_promotions_coupon_create()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_coupon(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/coupon"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update coupon promotion
-- Updates a coupon promotion.
-- /v2/project/{project_id}/admin/coupon/{external_id}
-- @name update_coupon_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body Create using body_promotions_coupon_update()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_coupon_promotion(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/coupon/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create coupon code
-- Creates coupon code.
-- /v2/project/{project_id}/admin/coupon/{external_id}/code
-- @name create_coupon_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body Create using body_promotions_create_coupon_promocode_code()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_coupon_code(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/coupon/{external_id}/code"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Generate coupon codes
-- Generates coupon codes.
-- /v2/project/{project_id}/admin/coupon/{external_id}/code/generate
-- @name generate_coupon_codes
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.generate_coupon_codes(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/coupon/{external_id}/code/generate"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Redeem promo code
-- Redeems a code of promo code promotion.
-- After redeeming a promo code, the user will get free items and/or the price of the cart and/or particular items will be decreased.
-- /v2/project/{project_id}/promocode/redeem
-- @name redeem_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_promotions_redeem_promo_code_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.redeem_promo_code(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/promocode/redeem"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Remove promo code from cart
-- Removes a promo code from a cart.
-- After the promo code is removed, the total price of all items in the cart will be recalculated without bonuses and discounts provided by a promo code.
-- /v2/project/{project_id}/promocode/remove
-- @name remove_cart_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_promotions_cancel_promo_code_model()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.remove_cart_promo_code(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/promocode/remove"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promocode_code}", uri.encode(tostring(promocode_code)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create promo code promotion
-- Creates a promo code promotion.
-- /v2/project/{project_id}/admin/promocode
-- @name create_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_promotions_promocode_create()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_promo_code(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/promocode"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update promo code promotion
-- Updates a promo code promotion.
-- /v2/project/{project_id}/admin/promocode/{external_id}
-- @name update_promo_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body Create using body_promotions_promocode_update()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_promo_code(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/promocode/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create code for promo code promotion
-- Creates code for a promo code promotion.
-- /v2/project/{project_id}/admin/promocode/{external_id}/code
-- @name create_promo_code_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body Create using body_promotions_create_coupon_promocode_code()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_promo_code_code(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/promocode/{external_id}/code"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Generate codes for promo code promotion
-- Generates codes for a promo code promotion.
-- /v2/project/{project_id}/admin/promocode/{external_id}/code/generate
-- @name generate_promo_code_codes
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.generate_promo_code_codes(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/promocode/{external_id}/code/generate"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_promotions_create_update_item_promotion()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_item_promotion(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/item"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_promotions_create_update_item_promotion()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_item_promotion(project_id, promotion_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/{promotion_id}/item"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promotion_id}", uri.encode(tostring(promotion_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promotion_id}", uri.encode(tostring(promotion_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promotion_id}", uri.encode(tostring(promotion_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_promotions_create_update_bonus_promotion()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_bonus_promotion(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/bonus"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_promotions_create_update_bonus_promotion()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_bonus_promotion(project_id, promotion_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/promotion/{promotion_id}/bonus"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promotion_id}", uri.encode(tostring(promotion_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promotion_id}", uri.encode(tostring(promotion_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promotion_id}", uri.encode(tostring(promotion_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{code}", uri.encode(tostring(code)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create virtual item
-- Creates a virtual item.
-- /v2/project/{project_id}/admin/items/virtual_items
-- @name admin_create_virtual_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_virtual_items_currency_admin_create_virtual_item()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_virtual_item(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_items"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{group_id}", uri.encode(tostring(group_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update virtual item
-- Updates a virtual item.
-- /v2/project/{project_id}/admin/items/virtual_items/sku/{item_sku}
-- @name admin_update_virtual_item
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_virtual_items_currency_admin_create_virtual_item()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_virtual_item(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_items/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create virtual currency
-- Creates a virtual currency.
-- /v2/project/{project_id}/admin/items/virtual_currency
-- @name admin_create_virtual_currency
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_virtual_items_currency_admin_create_virtual_currency()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_virtual_currency(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{virtual_currency_sku}", uri.encode(tostring(virtual_currency_sku)))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update virtual currency
-- Updates a virtual currency.
-- /v2/project/{project_id}/admin/items/virtual_currency/sku/{virtual_currency_sku}
-- @name admin_update_virtual_currency
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param virtual_currency_sku (REQUIRED) Virtual currency SKU.
-- @param body Create using body_virtual_items_currency_admin_create_virtual_currency()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_virtual_currency(project_id, virtual_currency_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(virtual_currency_sku)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency/sku/{virtual_currency_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{virtual_currency_sku}", uri.encode(tostring(virtual_currency_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{virtual_currency_sku}", uri.encode(tostring(virtual_currency_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create virtual currency package
-- Creates a virtual currency package.
-- /v2/project/{project_id}/admin/items/virtual_currency/package
-- @name admin_create_virtual_currency_package
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_virtual_items_currency_admin_create_virtual_currency_package()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_virtual_currency_package(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency/package"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update virtual currency package
-- Updates a virtual currency package.
-- /v2/project/{project_id}/admin/items/virtual_currency/package/sku/{item_sku}
-- @name admin_update_virtual_currency_package
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param promo_code Unique case sensitive code. Contains letters and numbers.
-- @param body Create using body_virtual_items_currency_admin_create_virtual_currency_package()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_virtual_currency_package(project_id, item_sku, promo_code, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/virtual_currency/package/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}
    query_params["locale"] = locale
    query_params["country"] = country
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["locale"] = locale
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{virtual_currency_sku}", uri.encode(tostring(virtual_currency_sku)))

    local query_params = {}
    query_params["locale"] = locale
    query_params["country"] = country
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{virtual_currency_package_sku}", uri.encode(tostring(virtual_currency_package_sku)))

    local query_params = {}
    query_params["locale"] = locale
    query_params["country"] = country
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["promo_code"] = promo_code

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
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

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_id}", uri.encode(tostring(item_id)))

    local query_params = {}
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{sku}", uri.encode(tostring(sku)))

    local query_params = {}
    query_params["promo_code"] = promo_code
    query_params["show_inactive_time_limited_items"] = show_inactive_time_limited_items

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create region
-- Creates region.
-- 
-- You can use a region for managing your regional restrictions.
-- /v2/project/{project_id}/admin/region
-- @name admin_create_region
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_create_update_region()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_region(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/region"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{region_id}", uri.encode(tostring(region_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_create_update_region()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_region(project_id, region_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(region_id)

    local url_path = "/v2/project/{project_id}/admin/region/{region_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{region_id}", uri.encode(tostring(region_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{region_id}", uri.encode(tostring(region_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Refresh all purchase limits for specified user
-- Refreshes all purchase limits across all items for a specified user so they can purchase these items again.
-- 
-- User limit API allows you to sell an item in a limited quantity. To configure the purchase limits, go to the Admin section of the desired item type module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- /v2/project/{project_id}/admin/user/limit/item/all
-- @name reset_all_user_items_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_reset_user_limits()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.reset_all_user_items_limit(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/item/all"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Refresh purchase limit
-- Refreshes the purchase limit for an item so a user can buy it again. If the *user* parameter is `null`, this call refreshes this limit for all users.
-- 
-- User limit API allows you to sell an item in a limited quantity. To configure the purchase limits, go to the Admin section of the desired item type module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- /v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}/all
-- @name reset_user_item_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_reset_user_limits_flexible()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.reset_user_item_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}/all"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get number of items available to specified user
-- Gets the remaining number of items available to the specified user within the limit applied.
-- 
-- User limit API allows you to sell an item in a limited quantity. To configure the purchase limits, go to the Admin section of the desired item type module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}
    query_params["user_external_id"] = user_external_id

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Increase number of items available to specified user
-- Increases the remaining number of items available to the specified user within the limit applied.
-- 
-- User limit API allows you to sell an item in a limited quantity. To configure the purchase limits, go to the Admin section of the desired item type module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- /v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}
-- @name add_user_item_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_update_user_limits_strict()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.add_user_item_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Set number of items available to specified user
-- Sets the number of items the specified user can buy within the limit applied after it was increased or decreased.
-- 
-- User limit API allows you to sell an item in a limited quantity. To configure the purchase limits, go to the Admin section of the desired item type module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- /v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}
-- @name set_user_item_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_update_user_limits_flexible()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.set_user_item_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Decrease number of items available to specified user
-- Decreases the remaining number of items available to the specified user within the limit applied.
-- 
-- User limit API allows you to sell an item in a limited quantity. To configure the purchase limits, go to the Admin section of the desired item type module:
-- * [Game Keys](https://developers.xsolla.com/api/igs/operation/admin-create-game/)
-- * [Virtual Items &amp; Currency](https://developers.xsolla.com/api/igs/operation/admin-get-virtual-items-list/)
-- * [Bundles](https://developers.xsolla.com/api/igs/operation/admin-get-bundle-list/)
-- /v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}
-- @name remove_user_item_limit
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_update_user_limits_strict()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.remove_user_item_limit(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/user/limit/item/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_reset_user_limits()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.reset_all_user_promotions_limit(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promotion/all"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_reset_user_limits_flexible()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.reset_user_promotion_limit(project_id, promotion_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}/all"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promotion_id}", uri.encode(tostring(promotion_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promotion_id}", uri.encode(tostring(promotion_id)))

    local query_params = {}
    query_params["user_external_id"] = user_external_id

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_update_user_limits_strict()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.add_user_promotion_limit(project_id, promotion_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promotion_id}", uri.encode(tostring(promotion_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_update_user_limits_flexible()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.set_user_promotion_limit(project_id, promotion_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promotion_id}", uri.encode(tostring(promotion_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_update_user_limits_strict()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.remove_user_promotion_limit(project_id, promotion_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(promotion_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promotion/id/{promotion_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{promotion_id}", uri.encode(tostring(promotion_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["user_external_id"] = user_external_id

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_update_promo_code_user_limits_strict()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.add_promo_code_user_promotion_limit(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promocode/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_update_promo_code_user_limits_flexible()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.set_promo_code_user_promotion_limit(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promocode/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_update_promo_code_user_limits_strict()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.remove_promo_code_user_promotion_limit(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/promocode/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["user_external_id"] = user_external_id

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_update_coupon_user_limits_strict()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.add_coupon_user_promotion_limit(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/coupon/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_update_coupon_user_limits_flexible()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.set_coupon_user_promotion_limit(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/coupon/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_update_coupon_user_limits_strict()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.remove_coupon_user_promotion_limit(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/user/limit/coupon/external_id/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["codes"] = codes
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["codes"] = codes
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create value point
-- Creates a value point.
-- /v2/project/{project_id}/admin/items/value_points
-- @name admin_create_value_points
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_create_value_point()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_value_points(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/items/value_points"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update value point
-- Updates a value point identified by an SKU.
-- /v2/project/{project_id}/admin/items/value_points/sku/{item_sku}
-- @name admin_update_value_point
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param item_sku (REQUIRED) Item SKU.
-- @param body Create using body_create_value_point()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_value_point(project_id, item_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(item_sku)

    local url_path = "/v2/project/{project_id}/admin/items/value_points/sku/{item_sku}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{item_sku}", uri.encode(tostring(item_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{value_point_sku}", uri.encode(tostring(value_point_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Set value points for items
-- Assigns value points to one or several items by an SKU. Users receive value points after they purchase these items.
-- 
-- Note that this PUT request overwrites all previously set value points for items in the project.
-- 
-- To avoid unintentional deletion of value points, include all items and their respective value points in each PUT request.
-- 
-- If you only want to update the value points for a specific item while preserving the value points of other items, you should retrieve the current set of value points using a GET request, modify the desired item&#x27;s value points, and then send the modified set of value points back with the updated value points for the specific item.
-- /v2/project/{project_id}/admin/items/{value_point_sku}/value_points/rewards
-- @name admin_set_items_value_point_reward
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param value_point_sku (REQUIRED) Value Point SKU.
-- @param body Create using body_set_item_value_point_reward()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_set_items_value_point_reward(project_id, value_point_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(value_point_sku)

    local url_path = "/v2/project/{project_id}/admin/items/{value_point_sku}/value_points/rewards"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{value_point_sku}", uri.encode(tostring(value_point_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
-- @param body Create using body_set_item_value_point_reward_for_patch()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_patch_items_value_point_reward(project_id, value_point_sku, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(value_point_sku)

    local url_path = "/v2/project/{project_id}/admin/items/{value_point_sku}/value_points/rewards"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{value_point_sku}", uri.encode(tostring(value_point_sku)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PATCH", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{value_point_sku}", uri.encode(tostring(value_point_sku)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(tostring(reward_chain_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(tostring(reward_chain_id)))
    url_path = url_path:gsub("{step_id}", uri.encode(tostring(step_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Get top 10 contributors to reward chain under clan
-- Retrieves the list of top 10 contributors to the specific reward chain under the current user&#x27;s clan. If a user doesn&#x27;t belong to a clan, the call returns an empty array.
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(tostring(reward_chain_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update current user&#x27;s clan
-- Updates a current user&#x27;s clan via user attributes. Claims all rewards from reward chains that were not claimed for a previous clan and returns them in the response. If the user was in a clan and now is not — their inclusion in the clan will be revoked. If the user changed the clan — the clan will be changed.
-- /v2/project/{project_id}/user/clan/update
-- @name user_clan_update
-- @param project_id (REQUIRED) Project ID.
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.user_clan_update(project_id, callback, retry_policy, cancellation_token)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/user/clan/update"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset
    query_params["enabled"] = enabled

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create reward chain
-- Creates reward chain.
-- /v2/project/{project_id}/admin/reward_chain
-- @name admin_create_reward_chain
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_create_reward_chain()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_reward_chain(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/reward_chain"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(tostring(reward_chain_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update reward chain
-- Updates particular reward chain.
-- /v2/project/{project_id}/admin/reward_chain/id/{reward_chain_id}
-- @name admin_update_reward_chain
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param reward_chain_id (REQUIRED) Reward chain ID.
-- @param body Create using body_update_reward_chain()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_update_reward_chain(project_id, reward_chain_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(reward_chain_id)

    local url_path = "/v2/project/{project_id}/admin/reward_chain/id/{reward_chain_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(tostring(reward_chain_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(tostring(reward_chain_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(tostring(reward_chain_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{reward_chain_id}", uri.encode(tostring(reward_chain_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create unique catalog offer promotion
-- Creates a unique catalog offer promotion.
-- /v2/project/{project_id}/admin/unique_catalog_offer
-- @name admin_create_unique_catalog_offer
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_promotions_unique_catalog_offer_create()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.admin_create_unique_catalog_offer(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Update unique catalog offer promotion
-- Updates the unique catalog offer promotion.
-- /v2/project/{project_id}/admin/unique_catalog_offer/{external_id}
-- @name update_unique_catalog_offer_promotion
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body Create using body_promotions_unique_catalog_offer_update()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.update_unique_catalog_offer_promotion(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer/{external_id}"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "DELETE", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Create unique catalog offer code
-- Creates unique catalog offer code.
-- /v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/code
-- @name create_unique_catalog_offer_code
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body Create using body_promotions_create_coupon_promocode_code()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.create_unique_catalog_offer_code(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/code"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}
    query_params["limit"] = limit
    query_params["offset"] = offset

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Generate unique catalog offer codes
-- Generates unique catalog offer codes.
-- /v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/code/generate
-- @name generate_unique_catalog_offer_codes
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param external_id (REQUIRED) Promotion external ID. Unique promotion identifier within the project.
-- @param body Create using body_()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.generate_unique_catalog_offer_codes(project_id, external_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)
    assert(external_id)

    local url_path = "/v2/project/{project_id}/admin/unique_catalog_offer/{external_id}/code/generate"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))
    url_path = url_path:gsub("{external_id}", uri.encode(tostring(external_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "PUT", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

--- Import items via JSON file
-- Imports items into the store from a JSON file via the specified URL. Refer to the [documentation](https://developers.xsolla.com/doc/in-game-store/how-to/json-import/) for more information about import from a JSON file.
-- /v1/projects/{project_id}/import/from_external_file
-- @name import_items_from_external_file
-- @param project_id (REQUIRED) Project ID. You can find this parameter in your [Publisher Account](https://publisher.xsolla.com/) next to the name of the project.
-- @param body Create using body_connector_import_items_body()
-- @param callback
-- @param retry_policy
-- @param cancellation_token
function M.import_items_from_external_file(project_id, body, callback, retry_policy, cancellation_token)
    assert(body)
    assert(project_id)

    local url_path = "/v1/projects/{project_id}/import/from_external_file"
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = body

    return http(callback, url_path, query_params, "POST", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
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
    url_path = url_path:gsub("{project_id}", uri.encode(tostring(project_id)))

    local query_params = {}

    local post_data = nil

    return http(callback, url_path, query_params, "GET", post_data, retry_policy, cancellation_token, function(result, err)
        return result, err
    end)
end

return M