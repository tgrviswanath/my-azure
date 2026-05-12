import azure.functions as func
import json
import os
from azure.cosmos import CosmosClient, exceptions

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

cosmos = CosmosClient.from_connection_string(os.environ["COSMOS_CONNECTION_STRING"])
db = cosmos.get_database_client("appdb")
container = db.get_container_client("items")


@app.route(route="items", methods=["GET"])
def list_items(req: func.HttpRequest) -> func.HttpResponse:
    items = list(container.read_all_items())
    return func.HttpResponse(json.dumps(items), mimetype="application/json")


@app.route(route="items/{id}", methods=["GET"])
def get_item(req: func.HttpRequest) -> func.HttpResponse:
    item_id = req.route_params.get("id")
    try:
        item = container.read_item(item=item_id, partition_key=item_id)
        return func.HttpResponse(json.dumps(item), mimetype="application/json")
    except exceptions.CosmosResourceNotFoundError:
        return func.HttpResponse("Not found", status_code=404)


@app.route(route="items", methods=["POST"])
def create_item(req: func.HttpRequest) -> func.HttpResponse:
    body = req.get_json()
    result = container.create_item(body=body)
    return func.HttpResponse(json.dumps(result), mimetype="application/json", status_code=201)


@app.route(route="items/{id}", methods=["DELETE"])
def delete_item(req: func.HttpRequest) -> func.HttpResponse:
    item_id = req.route_params.get("id")
    container.delete_item(item=item_id, partition_key=item_id)
    return func.HttpResponse(status_code=204)
