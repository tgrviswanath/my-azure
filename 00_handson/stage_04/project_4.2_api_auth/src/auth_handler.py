import azure.functions as func
import json
import os
import jwt
import requests

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

TENANT_ID = os.environ["AZURE_TENANT_ID"]
CLIENT_ID = os.environ["AZURE_CLIENT_ID"]
JWKS_URI = f"https://login.microsoftonline.com/{TENANT_ID}/discovery/v2.0/keys"


def validate_token(token: str) -> dict:
    """Validate Azure AD JWT token and return claims."""
    jwks = requests.get(JWKS_URI).json()
    public_keys = {}
    for key_data in jwks["keys"]:
        kid = key_data["kid"]
        public_keys[kid] = jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(key_data))

    header = jwt.get_unverified_header(token)
    key = public_keys[header["kid"]]

    return jwt.decode(
        token,
        key=key,
        algorithms=["RS256"],
        audience=CLIENT_ID,
        issuer=f"https://login.microsoftonline.com/{TENANT_ID}/v2.0",
    )


@app.route(route="protected", methods=["GET"])
def protected_endpoint(req: func.HttpRequest) -> func.HttpResponse:
    auth_header = req.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return func.HttpResponse("Unauthorized", status_code=401)

    token = auth_header[7:]
    try:
        claims = validate_token(token)
        return func.HttpResponse(
            json.dumps({"message": "Access granted", "user": claims.get("preferred_username")}),
            mimetype="application/json",
        )
    except jwt.InvalidTokenError as e:
        return func.HttpResponse(f"Forbidden: {e}", status_code=403)


@app.route(route="admin", methods=["GET"])
def admin_endpoint(req: func.HttpRequest) -> func.HttpResponse:
    auth_header = req.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return func.HttpResponse("Unauthorized", status_code=401)

    token = auth_header[7:]
    try:
        claims = validate_token(token)
        roles = claims.get("roles", [])
        if "Admin" not in roles:
            return func.HttpResponse("Forbidden: Admin role required", status_code=403)
        return func.HttpResponse(json.dumps({"message": "Admin access granted"}), mimetype="application/json")
    except jwt.InvalidTokenError as e:
        return func.HttpResponse(f"Forbidden: {e}", status_code=403)
