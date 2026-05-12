# Project 4.4 — Event-driven Image Processing

## What This Does
Blob upload triggers Azure Function → resizes image → stores output in separate container.

## Flow
```
Blob Upload → Event Grid → Azure Function → Resize → Output Blob
```

## How to Run
```bash
cd terraform && terraform init && terraform apply -auto-approve
# Upload an image to trigger processing
az storage blob upload --account-name <storage> --container-name uploads --file photo.jpg --name photo.jpg
```

## Lessons Learned
- Event Grid delivers blob events within seconds of upload
- Use Pillow for image processing in Python Functions
- Store processed images in separate container with different access tier
