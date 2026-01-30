# 🚀 AvaX-Gate Marketplace
**Next-Generation Interoperable NFT Marketplace on Avalanche L1**

AvaX-Gate is a high-performance, cross-L1 asset marketplace built on a sovereign Avalanche L1. It utilizes the **Avalanche Teleporter (ICM)** protocol to solve liquidity fragmentation across the Avalanche ecosystem, enabling seamless NFT trading between independent L1 chains.

---

## 🌟 Key Features

* **Cross-L1 Interoperability:** Integrated with **Avalanche Warp Messaging (AWM)** and **Teleporter** to facilitate secure cross-chain asset transfers.
* **Deflationary Tokenomics:** A protocol-level **10% automated fee burn** mechanism. Every successful trade destroys 10% of the transaction fee in the L1's native token to support ecosystem health.
* **Sovereign Infrastructure:** Deployed on a custom-configured Avalanche L1 for maximum scalability and low-latency transactions.
* **Secure Trading:** Built-in reentrancy protection and safe asset handling for virtual NFTs (vNFTs).

---

## 🛠 Technical Architecture

- **Blockchain:** Custom Avalanche L1 (Subnet)
- **ChainID:** `912345`
- **Smart Contract Framework:** Foundry
- **Cross-Chain Protocol:** Avalanche Teleporter (ICM)

### Deployed Contracts
| Contract | Address |
| :--- | :--- |
| **AvaLoomHub (Marketplace)** | `0xAC0D47BA951aA2245bEa677a7DF960300b7eFa71` |
| **Teleporter Messenger** | `0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf` |
| **Validator Manager / vNFT** | `0x0C0DEbA5E0000000000000000000000000000000` |

---

## 🚀 Installation & Deployment

To explore the smart contracts or deploy them to your local environment, follow these steps:

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed.
- Avalanche-CLI for L1 management.

### Build
```bash
forge build
