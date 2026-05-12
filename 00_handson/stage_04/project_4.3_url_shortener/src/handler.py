import azure.functions as func
import json
import os
import string
import random
from azure.cosmos import CosmosClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

cosmos = CosmosClient.from_connection_string(os.environ["COSMOS_CONNECTION_STRING"])
container = cosmos.get_database_client("urldb").get_container_client("urls")


def generate_code(length: int = 6) -> str:
    chars = string.ascii_letters + string.digits
    return "".join(random.choices(chars, k=length))


@app.route(route="shorten", methods=["POST"])
def shorten(req: func.HttpRequest) -> func.HttpResponse:
    body = req.get_json()
    original_url = body.get("url")
    if not original_url:
        return func.HttpResponse("Missing url", status_code=400)

    code = generate_code()
    item = {"id": code, "original_url": original_url, "clicks": 0}
    container.create_item(body=item)

    host = req.headers.get("Host", "localhost:7071")
    return func.HttpResponse(
        json.dumps({"short_code": code, "short_url": f"https://{host}/api/r/{code}"}),
        mimetype="application/json",
        status_code=201,
    )


@app.route(route="r/{code}", methods=["GET"])
def redirect(req: func.HttpRequest) -> func.HttpResponse:
    code = req.route_params.get("code")
    try:
        item = container.read_item(item=code, partition_key=code)
        # Increment click count
        item["clicks"] += 1
        container.replace_item(item=code, body=item)
        return func.HttpResponse(
            status_code=302,
            headers={"Location": item["original_url"]},
        )
    except Exception:
        return func.HttpResponse("Not found", status_code=404)
