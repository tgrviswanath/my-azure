# Steps — Project 4.4 Event-driven Image Processing

## Phase 1 — Deploy
```bash
cd terraform && terraform init && terraform apply -auto-approve
func azure functionapp publish func-image-processing-001
```

## Phase 2 — Test
```bash
# Upload image to trigger processing
az storage blob upload \
  --account-name stimgprocessing001 \
  --container-name uploads \
  --file ~/photo.jpg \
  --name photo.jpg

# Check processed container
az storage blob list \
  --account-name stimgprocessing001 \
  --container-name processed \
  --output table
```

## Screenshots to Take
- [ ] Image uploaded to uploads container
- [ ] Function triggered automatically
- [ ] Thumbnail in processed container
