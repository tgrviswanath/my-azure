# Architecture — Project 1.1 Static Website on Azure Storage + CDN

## Diagram

```
  User Browser
      │
      │ HTTPS request to www.yourdomain.com
      ▼
  ┌──────────────────────────────────────────────────────────┐
  │                  Azure CDN (Microsoft tier)              │
  │                                                          │
  │   Edge PoP (Point of Presence)                           │
  │   ┌─────────────────────────────────────────────────┐   │
  │   │  Cache HIT → serve from edge (< 10ms)           │   │
  │   │  Cache MISS → fetch from origin Storage         │   │
  │   └─────────────────────────────────────────────────┘   │
  │                                                          │
  │   mystaticsite-endpoint.azureedge.net                    │
  └──────────────────────────┬───────────────────────────────┘
                             │ Cache MISS: origin request
                             ▼
  ┌──────────────────────────────────────────────────────────┐
  │              Azure Storage Account                       │
  │              (Standard LRS, East US)                     │
  │                                                          │
  │   Static Website Feature                                 │
  │   ┌─────────────────────────────────────────────────┐   │
  │   │  $web container (special blob container)        │   │
  │   │                                                  │   │
  │   │  index.html    ← served for /                   │   │
  │   │  404.html      ← served for missing paths       │   │
  │   │  style.css                                       │   │
  │   │  app.js                                          │   │
  │   └─────────────────────────────────────────────────┘   │
  │                                                          │
  │   Primary endpoint:                                      │
  │   https://<account>.z13.web.core.windows.net            │
  └──────────────────────────────────────────────────────────┘
```

## DNS Flow

```
www.yourdomain.com
    │
    │ CNAME record
    ▼
mystaticsite-endpoint.azureedge.net
    │
    │ CDN resolves to nearest edge PoP
    ▼
Edge PoP (e.g., Chicago, London, Singapore)
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| `$web` container | Special Azure Storage container for static website files |
| Static website endpoint | Auto-generated URL: `https://<account>.z13.web.core.windows.net` |
| CDN endpoint | `https://<name>.azureedge.net` — globally cached version |
| Cache-Control | HTTP header controlling how long CDN caches content |
| CDN purge | Invalidates cached content at all edge nodes |
| Managed certificate | Free TLS cert provided by Azure CDN for custom domains |
| Origin host header | Must match storage account hostname for CDN to work |

## Deployment Flow

```
Developer
    │
    │ az storage blob upload-batch
    ▼
Azure Storage $web container
    │
    │ CDN fetches on first request (cache miss)
    ▼
Azure CDN Edge Nodes (worldwide)
    │
    │ Cached response
    ▼
End Users (< 50ms globally)
```
