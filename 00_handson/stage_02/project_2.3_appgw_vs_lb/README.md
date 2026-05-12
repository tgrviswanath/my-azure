# Project 2.3 — Application Gateway vs Azure Load Balancer

## What It Does

Side-by-side comparison lab of Azure's two main load balancing options:

| | Application Gateway | Azure Load Balancer |
|---|---|---|
| OSI Layer | L7 (HTTP/HTTPS) | L4 (TCP/UDP) |
| Routing | Path-based, host-based | Round-robin, hash |
| SSL | Termination + offload | Pass-through only |
| WAF | Built-in (WAF_v2) | Not available |
| Latency | Higher (L7 inspection) | Lower (packet-level) |
| Use case | Web apps, APIs | Any TCP/UDP workload |

## Azure Services Used

| Service | Purpose |
|---|---|
| Application Gateway Standard_v2 | L7 load balancing with path routing |
| Azure Load Balancer Standard | L4 TCP/UDP load balancing |
| VM Scale Sets (2x) | Backend pools for each LB |
| Public IPs (2x) | One per load balancer |
| Virtual Network | Shared network for both stacks |

## How to Deploy

```bash
cd terraform/
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Run the comparison test
```bash
pip install requests statistics
python code/load_test.py \
  --appgw-url http://<appgw-public-ip> \
  --lb-url http://<lb-public-ip> \
  --requests 200
```

### Cleanup
```bash
terraform destroy
```

## Lessons Learned

- **App Gateway adds ~5–20ms latency** vs Load Balancer due to L7 inspection — acceptable for web apps, not for real-time systems
- **Path-based routing** is App Gateway's killer feature: `/api/*` → backend A, `/static/*` → backend B
- **Load Balancer is stateless** — it doesn't inspect packets, just forwards based on 5-tuple hash
- **Health probes differ**: App GW uses HTTP probes (checks response code), LB uses TCP probes (checks port open)
- **SSL termination at App GW** reduces CPU load on backend VMs — they receive plain HTTP
- **Load Balancer is cheaper** — ~$18/month vs ~$125/month for App GW WAF_v2
- **Use both together**: LB for internal service-to-service, App GW for external web traffic

## Code

See `code/load_test.py` — sends HTTP requests to both endpoints, measures P50/P95/P99 latency, prints comparison table.
