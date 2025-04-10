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

# https://stackoverflow.com/a/19730306
def striphtml(s):
    # Remove well-formed tags, fixing mistakes by legitimate users
    no_tags = TAG_RE.sub('', s)
    # Clean up anything else by escaping
    ready_for_web = html.escape(no_tags)
    return ready_for_web

def capitalize(s):
    if len(s) == 0: return s
    return s[0].upper() + s[1:]

def render(data, templatefile, outfile):
    with open(templatefile, 'r') as f:
        template = f.read()
        result = pystache.render(template, data)
        with codecs.open(outfile, "wb", encoding="utf-8") as f:
            # f.write(result)
            f.write(unquote(result))



def load_api(path):
    with open(path, "r", encoding='utf-8') as f:
        api = json.load(f)
        return api


def lookup_component(ref, api):
    ref = ref.replace("#/components/", "")
    splits = ref.split("/")
    return api["components"][splits[0]][splits[1]]

def expand_ref(data, api):
    if "$ref" in data:
        component = lookup_component(data["$ref"], api)
        for k in component:
            data[k] = component[k]
        del data["$ref"]

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
            data["method"] = method.upper()
            data["path"] = path
            data["description"] = data["description"].strip()
            data["description"] = data["description"].replace("\n", "\n-- ")
            data["description"] = data["description"].replace("<br>", "\n-- ")
            data["description"] = striphtml(data["description"])
            data["operationId"] = data["operationId"].replace("-", "_")
            print("  ", data["path"], data["method"])
            api["paths"].append(data)

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


    # expand requestBody
    for data in api["paths"]:
        if "requestBody" not in data: continue
        expand_ref(data["requestBody"], api)


def process_request_bodies(api):
    print("processing request bodies")
    request_bodies = api["components"]["requestBodies"]
    api["components"]["requestBodies"] = []
    for request_body in request_bodies:
        data = request_bodies[request_body]
        data["id"] = request_body.replace("-", "_").lower()
        api["components"]["requestBodies"].append(data)
        if "application/json" in data["content"]:
            expand_ref(data["content"]["application/json"]["schema"], api)
            if "properties" in data["content"]["application/json"]["schema"]:
                properties = data["content"]["application/json"]["schema"]["properties"]
                data["content"]["application/json"]["schema"]["properties"] = []
                for prop_id in properties:
                    prop = properties[prop_id]
                    prop["id"] = prop_id
                    expand_ref(prop, api)
                    data["content"]["application/json"]["schema"]["properties"].append(prop)



api = load_api("openapi.json")

process_paths(api)
process_request_bodies(api)

render(api, "api_lua.mtl", "../xsolla/igs.lua")
