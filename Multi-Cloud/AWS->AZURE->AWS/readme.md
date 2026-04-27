# Connecting AWS and Azure — A Multi-Cloud VPN Deep Dive

![Status](https://img.shields.io/badge/Status-Live%20%E2%9C%85-brightgreen)
![Tunnels](https://img.shields.io/badge/IPSec%20Tunnels-4%2F4%20UP-blue)
![BGP Sessions](https://img.shields.io/badge/BGP%20Sessions-4%2F4%20Connected-blue)
![Encryption](https://img.shields.io/badge/Encryption-AES--256-orange)
![Protocol](https://img.shields.io/badge/Routing-BGP%20Dynamic-purple)

> *No physical cable. No Direct Connect. No ExpressRoute. Just encrypted tunnels, dynamic routing, and a lot of troubleshooting.*

---

## Table of Contents

1. [What Was Built](#1-what-was-built)
2. [Before You Begin — Core Concepts](#2-before-you-begin--core-concepts)
3. [Architecture Overview](#3-architecture-overview)
4. [IP Address Planning](#4-ip-address-planning)
5. [Azure Setup — Step by Step](#5-azure-setup--step-by-step)
6. [AWS Setup — Step by Step](#6-aws-setup--step-by-step)
7. [How Traffic Actually Flows](#7-how-traffic-actually-flows)
8. [Troubleshooting — Real Issues, Real Fixes](#8-troubleshooting--real-issues-real-fixes)
9. [Verification Checklist](#9-verification-checklist)

---

## 1. What Was Built

A **site-to-site VPN** between AWS (`us-east-1`) and Azure (`East US`) using:

| Component | Technology |
|---|---|
| Tunnel Protocol | IPSec (IKEv2) |
| Routing Protocol | BGP (Border Gateway Protocol) |
| AWS Hub | Transit Gateway (TGW) |
| Azure Gateway | VPN Gateway — VpnGw2AZ, Active-Active |
| Total Tunnels | **4 tunnels** (all active simultaneously) |
| Traffic | Fully encrypted end-to-end (AES-256) |

### What This Enables

```
AWS EC2 (172.31.x.x)  ←────────────────────→  Azure VM (10.1.x.x)
         ↑                                              ↑
   Private subnet                               Private subnet
   Encrypted tunnel                             Encrypted tunnel
```

Both clouds can reach each other's private subnets as if they were on the same internal network.

---

## 2. Before You Begin — Core Concepts

Don't skip this section. Understanding these four ideas will make every configuration decision below make complete sense.

### IPSec — The Encryption Layer

IPSec is what actually encrypts traffic between the two clouds. Think of it as a sealed envelope: whatever you put inside, nobody can read it in transit — not even ISPs sitting in the middle.

When an IPSec tunnel is "Up", it means the encryption handshake succeeded and both sides agreed on keys. But "Up" doesn't mean traffic flows — that depends on routing.

### BGP — The Routing Brain

BGP (Border Gateway Protocol) is the protocol the internet itself uses to exchange routing information. In this setup, AWS and Azure use BGP to automatically tell each other:

> *"I own the 172.31.0.0/16 range — send packets for that to me."*
> *"Got it. I own 10.1.0.0/16 — send those to me."*

Without BGP, even a healthy IPSec tunnel doesn't know **where** to send packets. BGP is what maps destinations to tunnel endpoints dynamically — no manual static routes needed.

### ASN — The Network's Identity Card

Every BGP participant needs an ASN (Autonomous System Number) — a unique ID that says "this is me" in the BGP world.

- **AWS Transit Gateway ASN:** `64512`
- **Azure VPN Gateway ASN:** `65000`

These must be different. BGP won't peer with itself.

### APIPA Tunnel IPs — BGP's Private Handshake

BGP sessions need IP addresses to communicate over. Inside a VPN tunnel, we use `169.254.x.x` (APIPA / link-local) addresses. These IPs only exist **inside** the tunnel — they're never exposed to the public internet and can't be reached from outside.

Each tunnel gets a `/30` subnet (4 IPs: network, AWS end, Azure end, broadcast) — exactly enough for a point-to-point link.

### The Relationship Between IPSec and BGP

```
IPSec UP + BGP UP = ✅ Traffic flows
IPSec UP + BGP DOWN = ❌ Traffic encrypted but nowhere to go
IPSec DOWN + BGP DOWN = ❌ No tunnel, no routing
```

This distinction matters enormously during troubleshooting.

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          AWS  (us-east-1)                           │
│                                                                     │
│  VPC: 172.31.0.0/16                                                 │
│  ┌──────────────────┐   ┌────────────────────────────────────────┐  │
│  │  Public Subnet   │   │        Transit Gateway (TGW)           │  │
│  │  172.31.0.0/20   │   │        ASN: 64512                      │  │
│  ├──────────────────┤   │                                        │  │
│  │  Private Subnet  │◄─►│  ┌────────────┐    ┌────────────────┐ │  │
│  │  172.31.80.0/20  │   │  │   VPN-1    │    │    VPN-2       │ │  │
│  └──────────────────┘   │  │ (→ Azure 0)│    │ (→ Azure 1)    │ │  │
│                          └──┬───────────┴────┴──────────┬──────┘  │
└─────────────────────────────┼──────────────────────────┼──────────┘
                              │   4 IPSec Tunnels         │
                              │   BGP over APIPA IPs      │
┌─────────────────────────────┼──────────────────────────┼──────────┐
│                    Azure    │   (East US)               │          │
│                             ▼                           ▼          │
│  VNet: 10.1.0.0/16                                                 │
│  ┌──────────────────┐   ┌────────────────────────────────────────┐ │
│  │  Public Subnet   │   │       VPN Gateway (azure-vpn-gw)       │ │
│  │  10.1.0.0/24     │   │       Active-Active Mode               │ │
│  ├──────────────────┤   │       ASN: 65000                       │ │
│  │  Private Subnet  │◄─►│       PIP-1: 52.151.225.100 (Inst. 0) │ │
│  │  10.1.2.0/24     │   │       PIP-2:  4.156.242.229 (Inst. 1) │ │
│  └──────────────────┘   └────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### Why This Design?

**AWS Transit Gateway as Hub** — Instead of creating VPN connections directly to each VPC, the Transit Gateway acts as a central router. Any VPC attached to it can reach Azure automatically. Scale to 10 VPCs later without rebuilding tunnels.

**Azure Active-Active Gateway** — Both Azure gateway instances handle traffic at the same time (not primary + standby). This gives 4 simultaneous tunnels and means a single instance failure doesn't cause an outage.

**BGP over Static Routes** — Routes are exchanged automatically. Adding a new subnet in either cloud doesn't require a config change on the other side — BGP propagates it.

---

## 4. IP Address Planning

> ⚠️ **The one rule that cannot be broken:** Network CIDRs across both clouds must never overlap. Overlapping CIDRs completely break VPN routing — packets don't know which direction to go.

### Network CIDRs

| Cloud | VNet / VPC | Public Subnet | Private Subnet | Region |
|---|---|---|---|---|
| AWS | 172.31.0.0/16 | 172.31.0.0/20 | 172.31.80.0/20 | us-east-1 |
| Azure | 10.1.0.0/16 | 10.1.0.0/24 | 10.1.2.0/24 | East US |

These ranges don't overlap — `172.31.x.x` and `10.1.x.x` are completely separate. ✅

### BGP APIPA Tunnel IPs

These IPs live *inside* the VPN tunnels. They are never reachable from the internet.

| Tunnel | AWS BGP IP | Azure BGP IP | Azure LNG |
|---|---|---|---|
| VPN1 — Tunnel 1 | 169.254.21.1 | 169.254.21.2 | aws-lng-1 |
| VPN1 — Tunnel 2 | 169.254.21.5 | 169.254.21.6 | aws-lng-2 |
| VPN2 — Tunnel 1 | 169.254.22.1 | 169.254.22.2 | aws-lng-3 |
| VPN2 — Tunnel 2 | 169.254.22.5 | 169.254.22.6 | aws-lng-4 |

Each pair uses a `/30` subnet — the smallest subnet that fits two endpoints. Network address, AWS IP, Azure IP, broadcast. Nothing wasted.

---

## 5. Azure Setup — Step by Step

### 5.1 Resource Group

```
Name:    multi-cloud-task
Region:  East US
```

Everything for this project lives inside one resource group. This makes cost tracking straightforward and cleanup surgical — deleting the resource group removes every resource created here.

> ⚠️ That last point cuts both ways. Don't delete the resource group unless you mean it.

---

### 5.2 Virtual Network (VNet)

```
Name:   az-multicloud-vnet
CIDR:   10.1.0.0/16
Region: East US
```

| Subnet | CIDR | Purpose |
|---|---|---|
| az-multicloud-vnet-public | 10.1.0.0/24 | Public-facing workloads |
| az-multicloud-vnet-private | 10.1.2.0/24 | Backend / secured workloads |
| GatewaySubnet | 10.1.3.0/27 | **VPN Gateway only — never deploy VMs here** |

**About `GatewaySubnet`:** Azure requires this subnet to be named exactly `GatewaySubnet` — no variations accepted. It's sized `/27` (32 IPs) as Microsoft recommends. Never attach an NSG to it. This is where Azure internally places the VPN Gateway VMs.

---

### 5.3 Network Security Group (NSG)

```
Name:          private-subnet-nsg
Attached to:   az-multicloud-vnet-private
```

| Priority | Rule | Source IP | Action |
|---|---|---|---|
| 100 | Allow-From-AWS | 172.31.0.0/16 | **Allow** |
| 65500 | DenyAllInBound | Any | Deny (default) |

The NSG is Azure's subnet-level firewall. Without priority 100, traffic arriving from AWS gets silently dropped here — even if the VPN tunnel is perfectly healthy. The tunnel would show "Connected" while no data flows through, which is a confusing failure mode.

> ⚠️ Attach the NSG to **`az-multicloud-vnet-private`** only — never to `GatewaySubnet`.

---

### 5.4 VPN Gateway

```
Name:          azure-vpn-gw
SKU:           VpnGw2AZ
Mode:          Active-Active
BGP:           Enabled
ASN:           65000

Public IPs:
  PIP-1: 52.151.225.100  (Instance 0)
  PIP-2:  4.156.242.229  (Instance 1)
```

**APIPA BGP IPs — set these in Gateway → Configuration:**

```
Instance 0 APIPA IPs:  169.254.21.2,  169.254.21.6
Instance 1 APIPA IPs:  169.254.22.2,  169.254.22.6
```

> ⚠️ **Critical:** All 4 APIPA IPs must be saved in the gateway configuration. Missing even one means that tunnel's BGP session never establishes — it stays "Connecting" indefinitely with no error message. This was the single hardest issue to debug in this project (see Troubleshooting section).

**Why `VpnGw2AZ`?** The `AZ` suffix means availability zone redundant — spread across multiple Azure datacenters. `VpnGw2` is the minimum tier that supports BGP + Active-Active. Never use the Basic SKU for multi-cloud setups; it doesn't support BGP.

> 💡 This is the most expensive resource here (~$250–$300/month). The gateway takes 20–45 minutes to provision and cannot be moved to another VNet after creation.

---

### 5.5 Route Table

```
Name:                     private-rt
Propagate gateway routes: Yes
Attached to:              az-multicloud-vnet-private
```

| Route | Destination | Next Hop |
|---|---|---|
| to-aws-vpc | 172.31.0.0/16 | Virtual network gateway |

This tells Azure VMs: *"packets headed for the AWS VPC go through the VPN Gateway."* Without this, Azure VMs send those packets to nowhere.

`Propagate gateway routes: Yes` allows BGP-learned routes to appear here automatically. If you connect a third cloud later, its routes propagate without manual updates.

---

### 5.6 Local Network Gateways (4 Total)

A Local Network Gateway (LNG) represents one AWS tunnel endpoint from Azure's perspective. You need one per AWS tunnel — four in total.

| LNG Name | AWS Public IP | AWS BGP IP | ASN |
|---|---|---|---|
| aws-lng-1 | 18.235.59.143 | 169.254.21.1 | 64512 |
| aws-lng-2 | 54.210.198.22 | 169.254.21.5 | 64512 |
| aws-lng-3 | 3.212.89.13 | 169.254.22.1 | 64512 |
| aws-lng-4 | 32.196.3.36 | 169.254.22.5 | 64512 |

Leave the "Address Space" field blank. BGP will advertise `172.31.0.0/16` from AWS automatically. Mixing static address spaces with BGP can create routing conflicts.

---

### 5.7 VPN Connections (4 Total)

Each connection is the link between the Azure VPN Gateway and one Local Network Gateway. It holds the Pre-Shared Key (PSK) and binds a specific APIPA IP to that tunnel.

| Connection | LNG | Azure BGP IP | IKE |
|---|---|---|---|
| aws-conn-1 | aws-lng-1 | 169.254.21.2 | IKEv2 |
| aws-conn-2 | aws-lng-2 | 169.254.21.6 | IKEv2 |
| aws-conn-3 | aws-lng-3 | 169.254.22.2 | IKEv2 |
| aws-conn-4 | aws-lng-4 | 169.254.22.6 | IKEv2 |

**Settings for each connection:**
- Connection type: Site-to-site (IPsec)
- IKE Protocol: IKEv2
- Enable BGP: ✅ Yes
- Enable Custom BGP Address: ✅ Yes (specify the APIPA IP per tunnel)

> ⚠️ The PSK must match **exactly** on both AWS and Azure sides — every character, including symbols. One wrong character means the tunnel never comes up. No error, just silence.

---

## 6. AWS Setup — Step by Step

### 6.1 Transit Gateway

```
Name:   multi-cloud-tgw
ID:     tgw-0eec593372aa674bf
ASN:    64512
```

The Transit Gateway is AWS's central routing hub. Every VPC and every VPN connection attaches to it. Instead of a mesh of direct connections, everything connects once to the TGW and it handles the rest.

---

### 6.2 TGW Attachment — VPC

```
Name:   aws-vpc-attachment
Type:   VPC
VPC:    vpc-055aeedd081a8d339
State:  Available ✅
```

This attachment is what allows the TGW to route traffic into your VPC. Without it, the TGW handles the routing but packets have nowhere to land.

---

### 6.3 Customer Gateways (2 Total)

A Customer Gateway (CGW) represents one Azure VPN Gateway instance from AWS's perspective.

| Name | Azure Public IP | BGP ASN |
|---|---|---|
| azure-instance-0 | 52.151.225.100 | 65000 |
| azure-instance-1 | 4.156.242.229 | 65000 |

---

### 6.4 Site-to-Site VPN Connections (2 Total)

Two VPN connections — one to each Azure gateway instance. Each connection has two tunnels, giving 4 total.

**VPN-1 → Azure Instance 0 (`52.151.225.100`)**

```
ID:      vpn-0aec7c1adc4fbf949
Target:  Transit Gateway
Routing: Dynamic (BGP)
```

| | Tunnel 1 | Tunnel 2 |
|---|---|---|
| AWS Outside IP | 18.235.59.143 | 54.210.198.22 |
| Azure Outside IP | 52.151.225.100 | 52.151.225.100 |
| AWS BGP IP | 169.254.21.1 | 169.254.21.5 |
| Azure BGP IP | 169.254.21.2 | 169.254.21.6 |
| Inside CIDR | 169.254.21.0/30 | 169.254.21.4/30 |

**VPN-2 → Azure Instance 1 (`4.156.242.229`)**

```
ID:      vpn-08941c2d0763311ef
Target:  Transit Gateway
Routing: Dynamic (BGP)
```

| | Tunnel 1 | Tunnel 2 |
|---|---|---|
| AWS Outside IP | 3.212.89.13 | 32.196.3.36 |
| Azure Outside IP | 4.156.242.229 | 4.156.242.229 |
| AWS BGP IP | 169.254.22.1 | 169.254.22.5 |
| Azure BGP IP | 169.254.22.2 | 169.254.22.6 |
| Inside CIDR | 169.254.22.0/30 | 169.254.22.4/30 |

---

### 6.5 TGW Route Table

```
ID: tgw-rtb-0472e4bc793518f94
```

**Associations** (what attaches to this route table):

| Attachment | Type | State |
|---|---|---|
| aws-vpc-attachment | VPC | Associated ✅ |
| VPN-1 attachment | VPN | Associated ✅ |
| VPN-2 attachment | VPN | Associated ✅ |

**Propagations** (what BGP routes are accepted):

| Attachment | Type | State |
|---|---|---|
| VPC attachment | VPC | Enabled ✅ |
| VPN-1 attachment | VPN | Enabled ✅ |
| VPN-2 attachment | VPN | Enabled ✅ |

Propagation is what makes BGP-learned routes (like `10.1.0.0/16` from Azure) actually appear in the TGW route table. Without it, BGP sessions come up, routes are exchanged, and then silently ignored. Traffic never flows, and there's no obvious error.

> ⚠️ **Blackhole Warning:** Never manually add a static route for `10.1.0.0/16` in the TGW route table. If the tunnel is down when you create it, it becomes a Blackhole route — it persists even after the tunnel comes back up and blocks BGP-propagated routes from taking effect.

---

### 6.6 VPC Route Table

```
ID:  rtb-0f38634e93a8c221d
VPC: vpc-055aeedd081a8d339
```

| Destination | Target | Status |
|---|---|---|
| 172.31.0.0/16 | local | Active ✅ |
| 10.1.0.0/16 | tgw-0eec593372aa674bf | Active ✅ |
| 0.0.0.0/0 | igw-0d6c8340a2d2f4af1 | Active ✅ |

The `10.1.0.0/16 → TGW` entry is what tells EC2 instances how to reach Azure. Without it, packets to `10.1.x.x` hit the internet gateway and get lost.

---

## 7. How Traffic Actually Flows

### AWS EC2 → Azure VM

```
AWS EC2 (172.31.80.10)
    │
    │  Destination: 10.1.2.50
    │
    ▼
VPC Route Table
    │  10.1.0.0/16 → Transit Gateway
    ▼
Transit Gateway
    │  TGW Route Table: 10.1.0.0/16 → VPN-1 (BGP-learned)
    ▼
IPSec Tunnel (encrypted, over public internet)
    │  AWS Outside IP → Azure Public IP
    ▼
Azure VPN Gateway
    │  Decrypts packet
    │  Routes to: 10.1.0.0/16 → local VNet
    ▼
Azure VM (10.1.2.50) ✅
```

The same path works in reverse for Azure → AWS.

### What BGP Does Behind the Scenes

```
AWS TGW (ASN 64512)                    Azure VPN GW (ASN 65000)
         │                                        │
         │  "I have 172.31.0.0/16"               │
         │ ──────────────────────────────────────►│
         │                                        │  (Azure installs route)
         │        "I have 10.1.0.0/16"            │
         │◄────────────────────────────────────── │
         │  (AWS TGW installs route)               │
         │                                        │
         │  No manual configuration needed        │
```

BGP is what makes this "just work" — once tunnels are up, both sides automatically know each other's subnets and install the routes without any manual intervention.

---

## 8. Troubleshooting — Real Issues, Real Fixes

### Issue 1: Tunnels show "IPSEC IS UP" but overall Status = Down

**What it looked like:** AWS console showed the tunnel detail as `IPSEC IS UP` but the Status column showed `Down`. Everything seemed fine but nothing worked.

**What it meant:** IPSec handshake succeeded — encryption was working. But BGP session failed to start.

**Root cause:** The 4 APIPA IPs (`169.254.21.2`, `169.254.21.6`, `169.254.22.2`, `169.254.22.6`) were not saved in the Azure VPN Gateway Configuration page. Azure had nothing to respond on, so BGP TCP connections never completed.

**Fix:** Go to `azure-vpn-gw` → **Configuration** → fill in all 4 APIPA IPs in the two custom APIPA fields (2 per field). Save. Wait ~60 seconds for the gateway to restart.

---

### Issue 2: TGW Route for `10.1.0.0/16` showing as BLACKHOLE

**What it looked like:** TGW Route Table showed `10.1.0.0/16` with state `Blackhole` even after tunnels came up.

**Root cause:** A manual static route for `10.1.0.0/16` was added to the TGW route table while the VPN was down. When the attachment is down, static routes become Blackhole routes. They persist even after recovery and block the BGP-propagated route from being installed.

**Fix:** Delete the manual static route entirely. BGP will automatically propagate and install the correct route as `Active` once the tunnels are healthy.

---

### Issue 3: All Azure BGP Peers stuck in "Connecting"

**What it looked like:** Azure VPN Gateway BGP Peers page showed all 4 AWS APIPA peers (`169.254.21.1`, `169.254.21.5`, `169.254.22.1`, `169.254.22.5`) stuck in `Connecting` indefinitely.

**Root cause:** Same as Issue 1 — Azure had no APIPA addresses configured to respond on. BGP sessions were being initiated by AWS but Azure couldn't respond on the expected IPs.

**Fix:** Register all 4 APIPA IPs on the gateway (as above). Both Issue 1 and Issue 3 had the same root cause and the same fix.

---

## 9. Verification Checklist

### Azure

- [ ] VNet `10.1.0.0/16` created with no CIDR overlap with AWS
- [ ] `GatewaySubnet` at `10.1.3.0/27` — no VMs, no NSG attached
- [ ] NSG `private-subnet-nsg` allows `172.31.0.0/16` inbound, attached to private subnet
- [ ] VPN Gateway: SKU `VpnGw2AZ`, Active-Active ON, BGP ON, ASN `65000`
- [ ] All 4 APIPA IPs set in Gateway → Configuration (`169.254.21.2`, `169.254.21.6`, `169.254.22.2`, `169.254.22.6`)
- [ ] 4 Local Network Gateways — correct AWS public IPs and BGP peer IPs
- [ ] 4 Connections — correct PSKs, IKEv2, BGP enabled, Custom BGP Address set per connection
- [ ] Route table `private-rt` — route `172.31.0.0/16 → VPN Gateway`, attached to private subnet
- [ ] All 4 Connections show **Connected**

### AWS

- [ ] Transit Gateway created with ASN `64512`
- [ ] VPC attachment created, state `Available`
- [ ] 2 Customer Gateways — one per Azure public IP, ASN `65000`
- [ ] 2 VPN Connections targeting TGW, with correct APIPA inside CIDRs and PSKs matching Azure
- [ ] TGW Route Table: all 3 attachments associated
- [ ] TGW Route Table: propagation enabled for all 3 attachments
- [ ] VPC Route Table: `10.1.0.0/16 → TGW` added to private subnet route table
- [ ] Both VPN connections show `Available`, all 4 tunnels show `UP`

### Final Test

```bash
# From an EC2 instance in the AWS private subnet (172.31.80.x):
ping 10.1.2.x
# Expected: Reply from 10.1.2.x — bytes=32 time=<ms>

# From an Azure VM in the private subnet (10.1.2.x):
ping 172.31.80.x
# Expected: 64 bytes from 172.31.80.x — icmp_seq=1 ttl=... time=... ms
```

Both pings should succeed. If they do, all four layers are working: IPSec encryption, BGP routing, NSG rules, and VPC/VNet route tables.

---

## Quick Reference

| Resource | AWS | Azure |
|---|---|---|
| Network CIDR | 172.31.0.0/16 | 10.1.0.0/16 |
| Private Subnet | 172.31.80.0/20 | 10.1.2.0/24 |
| BGP ASN | 64512 | 65000 |
| Gateway | Transit Gateway | VPN Gateway (VpnGw2AZ) |
| Tunnel Count | 4 (2 connections × 2) | 4 (Active-Active × 2) |
| Routing | BGP Dynamic | BGP Dynamic |
| Encryption | IPSec / IKEv2 / AES-256 | IPSec / IKEv2 / AES-256 |

---

*Setup completed: April 2026*
*All tunnels operational: 4/4 ✅ | BGP sessions active: 4/4 ✅*
