import azure.functions as func
import json
import os
from io import BytesIO
from PIL import Image
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp()

STORAGE_CONN = os.environ["STORAGE_CONNECTION_STRING"]
OUTPUT_CONTAINER = "processed"
THUMBNAIL_SIZE = (300, 300)


@app.blob_trigger(arg_name="blob", path="uploads/{name}", connection="STORAGE_CONNECTION_STRING")
def process_image(blob: func.InputStream) -> None:
    blob_name = blob.name.split("/")[-1]
    print(f"Processing image: {blob_name}")

    # Read and resize
    image_data = blob.read()
    img = Image.open(BytesIO(image_data))
    img.thumbnail(THUMBNAIL_SIZE)

    # Save to output container
    output = BytesIO()
    fmt = img.format or "JPEG"
    img.save(output, format=fmt)
    output.seek(0)

    client = BlobServiceClient.from_connection_string(STORAGE_CONN)
    output_blob = client.get_blob_client(container=OUTPUT_CONTAINER, blob=f"thumb_{blob_name}")
    output_blob.upload_blob(output, overwrite=True)

    print(f"✅ Thumbnail saved: thumb_{blob_name} ({img.size[0]}x{img.size[1]})")
