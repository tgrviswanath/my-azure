# Project 1.1 — Static Website on Azure Storage + CDN

## What This Does
Hosts a static website on Azure Blob Storage with Azure CDN for global distribution, HTTPS, and custom domain support. This is the Azure equivalent of S3 + CloudFront.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure Storage Account | Hosts static website files ($web container) |
| Azure CDN (Microsoft tier) | Global edge caching and HTTPS |
| Azure DNS Zone | Custom domain management |
| Azure Storage Static Website | Built-in static hosting feature |

## How to Deploy
```bash
cd terraform
terraform init
terraform apply -auto-approve

# Deploy website files
bash code/deploy_website.sh
```

## Folder Structure
```
project_1.1_static_website/
├── README.md
├── steps.md
├── cost_estimate.md
├── docs/
│   └── architecture.md
├── terraform/
│   └── main.tf
└── code/
    ├── deploy_website.sh
    └── index.html
```

## Lessons Learned
- Azure Storage static website uses a special `$web` container
- Enable static website BEFORE uploading files — it creates the `$web` container
- CDN endpoint URL format: `<endpoint-name>.azureedge.net`
- CDN cache purge takes 2-5 minutes to propagate globally
- Set `Cache-Control: max-age=3600` on blobs for proper CDN caching
- Custom domain HTTPS requires CDN — Storage alone only supports HTTP
- `az cdn endpoint purge` clears CDN cache after deploying new content

## URLs After Deployment
- Storage endpoint: `https://<account>.z13.web.core.windows.net`
- CDN endpoint: `https://<endpoint>.azureedge.net`
- Custom domain: `https://www.yourdomain.com` (after DNS setup)
