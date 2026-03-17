# 🌐 Google Cloud Platform (GCP) Deployment Guide

This guide will walk you through deploying the **NSE Option Chain Bot** to a Google Cloud Compute Engine Virtual Machine (VM).

---

## 📋 Prerequisites
1.  **Google Cloud Account** with billing enabled.
2.  **GitHub Repository Created**: Run `push_to_github.bat` on your local machine to upload your code first.

---

## 🛠️ Step 1: Create a Google Cloud VM (Compute Engine)

1.  Go to the [GCP Console](https://console.cloud.google.com/).
2.  Navigate to **Compute Engine > VM instances**.
3.  Click **Create Instance**.
4.  **Configure Instance**:
    *   **Name**: `nse-trading-system`
    *   **Region/Zone**: Choose one close to you (e.g., `asia-south1` for Mumbai).
    *   **Machine configuration**: 
        *   **Series**: `E2`
        *   **Machine type**: `e2-medium` (2 vCPUs, 4 GB memory) - *Recommended for stability*.
    *   **Boot disk**:
        *   Click **Change**.
        *   **Operating System**: `Ubuntu`
        *   **Version**: `Ubuntu 22.04 LTS`
        *   **Size**: `20 GB` (Standard persistent disk is fine).
    *   **Firewall**:
        *   Check **Allow HTTP traffic**.
        *   Check **Allow HTTPS traffic**.
5.  Click **Create**. Wait for the VM to start.

---

## 🔑 Step 2: Connect via SSH and Install Docker

1.  In the VM Instances list, click the **SSH** button next to your instance.
2.  A terminal window will open. Run the following commands:

### Update System
```bash
sudo apt update && sudo apt upgrade -y
```

### Install Docker & Docker Compose
```bash
sudo apt install -y docker.io docker-compose
```

### Verify Installations
```bash
docker --version
docker-compose --version
```

---

## 📂 Step 3: Clone Your Code

1.  Clone your GitHub repository onto the VM (Replace with your repo link):
    ```bash
    git clone https://github.com/mybullandbear/RiteshPersonalChart.git
    ```
2.  Navigate into the project directory:
    ```bash
    cd RiteshPersonalChart
    # If the files are in a subfolder:
    # cd OldNSESystemforTrading-main
    ```

---

## 🚀 Step 4: Run with Docker Compose

1.  Run the application using Docker Compose (it will build and run in the background):
    ```bash
    sudo docker-compose up --build -d
    ```
2.  Check if containers are running:
    ```bash
    sudo docker ps
    ```
    *You should see 3 containers: `backend`, `fetcher`, and `frontend`.*

---

## 🛡️ Step 5: Configure GCP Firewall (Crucial)

By default, GCP blocks access to ports 5000 (Backend) and 8080 (Frontend). You must open them.

1.  In GCP Console, search for **VPC Network > Firewall**.
2.  Click **Create Firewall Rule**.
3.  **Configure Rule**:
    *   **Name**: `allow-nse-ports`
    *   **Targets**: `All instances in the network`
    *   **Source filter**: `IPv4 ranges`
    *   **Source IPv4 ranges**: `0.0.0.0/0` (Allows anyone to access - *or set to your IP for safety*).
    *   **Protocols and ports**:
        *   Check **Specified protocols and ports**.
        *   Check **TCP**.
        *   Enter: `5000, 8080`
4.  Click **Create**.

---

## 🎯 Step 6: Access the Dashboard

1.  Find your VM's **External IP** in the Compute Engine dashboard.
2.  Open your browser and navigate to:
    ```
    http://<YOUR_VM_EXTERNAL_IP>:8080
    ```

---

## 💡 Pro-Tip: Use Port 80 (Standard Web Port)

If you want to access the dashboard without typing `:8080`, edit the `docker-compose.yml` file on the VM:
```bash
nano docker-compose.yml
```
Change line 31 from `"8080:80"` to `"80:80"`.
Save and exit (`CTRL+O`, `Enter`, `CTRL+X`).
Then restart:
```bash
sudo docker-compose down
sudo docker-compose up -d
```
Now access via `http://<YOUR_VM_EXTERNAL_IP>`.
