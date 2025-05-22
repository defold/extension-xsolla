#!/usr/bin/env python

import os
import sys
import shutil
import json
import re
import html
import codecs
import fnmatch
import pystache
from urllib.parse import unquote

TAG_RE = re.compile(r'(<!--.*?-->|<[^>]*>)')
PRIMITIVE_TYPES = [ "integer", "number", "string", "boolean"]

# https://stackoverflow.com/a/19730306
def striphtml(s):
    # Remove well-formed tags, fixing mistakes by legitimate users
    no_tags = TAG_RE.sub('', s)
    return no_tags
    # # Clean up anything else by escaping
    # ready_for_web = html.escape(no_tags)
    # return ready_for_web

def is_primitive_type(t):
    return t in PRIMITIVE_TYPES

def is_primitive_python_type(o):
    return isinstance(o, str) or isinstance(o, bool) or isinstance(o, int) or isinstance(o, float) or o is None

def python_to_lua_type(o):
    if isinstance(o, str):
        return "\"" + o + "\""
    elif isinstance(o, bool):
        return ("true" if o else "false")
    elif isinstance(o, int) or isinstance(o, float):
        return str(o)
    elif o is None:
        return "nil"
    else:
        return {}

def tolua(o, prefix = "-- ", suffix = ""):
    s = ""
    if isinstance(o, list):
        s = s + prefix + "{\n"
        for v in o:
            s = s + tolua(v, prefix + "  ", ",")
        s = s + prefix + "}" + suffix + "\n"
    elif isinstance(o, dict):
        s = s + prefix + "{\n"
        for k in o:
            v = o[k]
            if is_primitive_python_type(v):
                s = s + prefix + "  " + k + " = " + tolua(v, "", ",")
            else:
                s = s + prefix + "  " + k + " = \n" + tolua(v, prefix + "  ", ",")
        s = s + prefix + "}" + suffix + "\n"
    else:
        s = s + prefix + python_to_lua_type(o) + suffix + "\n"
    return s

def capitalize(s):
    if len(s) == 0: return s
    return s[0].upper() + s[1:]

def render(data, templatefile, outfile):
    with open(templatefile, 'r') as f:
        template = f.read()
        result = pystache.render(template, data)
        with codecs.open(outfile, "wb", encoding="utf-8") as f:
            f.write(unquote(result))


def cleanstring_singleline(s):
    s = s.strip()
    s = s.replace("\n", ". ")
    s = s.replace("<br>", ". ")
    s = striphtml(s)
    return s

def cleanstring_multiline(s, linebreak = "\n-- "):
    s = s.strip()
    s = s.replace("\n", linebreak)
    s = s.replace("<br><br>", linebreak)
    s = s.replace("<br> ", linebreak)
    s = s.replace("<br>", linebreak)
    s = striphtml(s)
    return s

def load_api(path):
    with open(path, "r", encoding='utf-8') as f:
        api = json.load(f)
        return api

def lookup_component(ref, api):
    ref = ref.replace("#/components/", "")
    splits = ref.split("/")
    component_type = splits[0]
    component_id = splits[1]
    component = api["components"][component_type][component_id]
    component["id"] = component_id.replace("-", "_").lower()
    return component

def expand_ref(data, api):
    if "$ref" in data:
        component = lookup_component(data["$ref"], api)
        for k in component:
            data[k] = component[k]
        del data["$ref"]

def expand_array(arr, api):
    assert arr["type"] == "array"
    if "items" in arr:
        expand(arr["items"], api)

def expand_object(obj, api):
    assert obj["type"] == "object"
    if "properties" in obj:
        properties = obj["properties"]
        if isinstance(properties, dict):
            obj["properties"] = []
            for prop_id in properties:
                prop = properties[prop_id]
                prop["id"] = prop_id
                obj["properties"].append(prop)

        for prop in obj["properties"]:
            expand(prop, api)
            prop["description"] = cleanstring_multiline(prop.get("description", ""))

def expand(v, api):
    expand_ref(v, api)
    if "oneOf" in v:
        v["type"] = "oneof"
        v["isoneof"] = True
        for o in v["oneOf"]:
            expand(o, api)
    elif "allOf" in v:
        v["type"] = "allof"
        v["isallof"] = True
        for o in v["allOf"]:
            expand(o, api)
    elif v["type"] == "object":
        v["isobject"] = True
        expand_object(v, api)
        if v.get("properties"):
            v["hasproperties"] = True
    elif v["type"] == "array":
        v["isarray"] = True
        expand_array(v, api)
    elif not is_primitive_type(v["type"]):
        error("Unable to expand", v["type"])

def property_to_example(prop, api):
    example = None
    if prop["type"] == "string":
        example = prop.get("example", prop.get("description", ""))
    elif prop["type"] == "boolean":
        example = prop.get("example", True)
    elif prop["type"] == "number":
        example = prop.get("example", 123.456)
    elif prop["type"] == "integer":
        example = prop.get("example", 123)
    elif prop["type"] == "oneof":
        example = property_to_example(prop["oneOf"][0], api)
    elif prop["type"] == "array":
        example = []
        example.append(property_to_example(prop["items"], api))
    elif prop["type"] == "object":
        example = {}
        properties = prop.get("properties", {})
        if isinstance(properties, list):
            for p in properties:
                example[p["id"]] = property_to_example(p, api)
        else:
            for prop_id in properties:
                p = prop["properties"][prop_id]
                example[prop_id] = property_to_example(p, api)
    else:
        print("Unknown type", prop["type"])
        sys.exit(4)
    return example

def dict_to_array(d):
    a = []
    for k in d:
        v = {
            "key": k,
            "value": d[k],
        }
        a.append(v)
    return a

def process_paths(api):
    print("processing paths")
    # merge paths+methods and convert into list
    paths = api["paths"]
    api["paths"] = []
    for path in paths:
        for method in paths[path]:
            data = paths[path][method]
            if data.get("x-admin") or data.get("x-server"):
                continue
            data["method"] = method.upper()
            data["path"] = path
            data["description"] = cleanstring_multiline(data["description"])
            data["operationId"] = data["operationId"].replace("-", "_")
            print("  ", data["path"], data["method"])
            api["paths"].append(data)

    # convert security schemes
    for data in api["paths"]:
        security = []
        for scheme in data.get("security", {}):
            scheme_id = None
            if "XsollaLoginUserJWT" in scheme:
                scheme_id = "XsollaLoginUserJWT"
            elif "basicAuth" in scheme:
                scheme_id = "basicAuth"
            elif "AuthForCart" in scheme:
                scheme_id = "AuthForCart"
            elif "basicMerchantAuth" in scheme:
                scheme_id = "basicMerchantAuth"
            else:
                print("Unknown security scheme", scheme_id)
                sys.exit(1)
            security.append({
                scheme_id: True,
                "scheme": scheme_id,
                "description": cleanstring_multiline(api["components"]["securitySchemes"][scheme_id]["description"])
            })
        data["security"] = security

    # convert response codes to list
    for data in api["paths"]:
        responses = data["responses"]
        data["responses"] = []
        for code in responses:
            response = responses[code]
            response["code"] = code
            expand_ref(response, api)
            data["responses"].append(response)

    # expand parameters
    for data in api["paths"]:
        for parameter in data["parameters"]:
            expand_ref(parameter, api)
            parameter["inpath"] = parameter["in"] == "path"
            parameter["inquery"] = parameter["in"] == "query"
            parameter["name"] = parameter["name"].replace("[]", "")
            parameter["name"] = parameter["name"].replace("-", "_")

    # expand requestBody and create example
    for data in api["paths"]:
        if "requestBody" not in data: continue
        expand_ref(data["requestBody"], api)
        if "application/json" not in data["requestBody"]["content"]:
            print("Expected content encoding JSON")
            sys.exit(1)
        schema = data["requestBody"]["content"]["application/json"]["schema"]
        if "properties" in schema:
            properties = schema["properties"]
            for prop_id in schema["properties"]:
                expand(schema["properties"][prop_id], api)
        if "example" not in schema:
            schema["example"] = property_to_example(schema, api)
        data["requestBodyLuaExample"] = tolua(schema["example"], "-- ", "\n").strip()

api = load_api("openapi.json")

process_paths(api)

# with open("apidump.json", 'w') as f:
#     f.write(json.dumps(api, indent = 2))

render(api, "api_lua.mtl", "../xsolla/shop.lua")
