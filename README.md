# Injective Node Docker

This repository provides Docker Compose configurations for running an Injective RPC node.

It’s designed to work with [central-proxy-docker](https://github.com/CryptoManufaktur-io/central-proxy-docker) for Traefik and Prometheus remote write. If you need external network connectivity, include `:ext-network.yml` in your `COMPOSE_FILE` (as set in your `.env` file).

## Quick Setup

1. **Prepare your environment:**
   Copy the default environment file and update your settings:
   ```bash
   cp default.env .env
   nano .env
   ```
   Update values such as `MONIKER`, `NETWORK`, and `SNAPSHOT`.

2. **Expose RPC Ports (Optional):**
   If you want the node’s RPC ports exposed locally, include `rpc-shared.yml` in your `COMPOSE_FILE` within `.env`.

3. **Install Docker (if needed):**
   Run:
   ```bash
   ./injectived install
   ```
   This command installs Docker CE if it isn’t already installed.

4. **Start the Node:**
   Bring up your Injective RPC node by running:
   ```bash
   ./injectived up
   ```

5. **Software Updates:**
   To update the node software, run:
   ```bash
   ./injectived update
   ./injectived up
   ```

## Snapshot and Genesis Setup

When you first start the node, the container will:

- **Initialize the node:**
  Run `injectived init` with your specified `MONIKER` and `NETWORK`.
- **Download the genesis file:**
  It retrieves the genesis file from the official Injective mainnet repository.
- **Download seeds:**
  The configuration is updated with a list of seed nodes.
- **Download and extract a snapshot (if provided):**
  If the `SNAPSHOT` environment variable is set, the snapshot will be downloaded via `aria2c` and then extracted into the node’s data directory using a pipeline that displays progress.

## Key setup

All keys for the validator should be stored in the `keys/*` directories
* `consensus` is the validator key. It can be created using the following command.
```bash
  docker compose --profile tools run create-validator-keys
```
To back these keys up to your local `keys/consensus` directory, run the following command:
```bash
docker compose --profile tools run export-validator-keys
```
* `operator` keys are used as the delegated operator for this validator to perform signing duties on behalf of the validtor.  To create these keys run:
```bash
  docker compose --profile tools run create-operator-wallet
```
* ethereum-peggo is an Ethereum key that Injective uses to sign txs on Ethereum.  You can follow [instructions on the Injective docs](https://docs.injective.network/infra/validator-mainnet/peggo#managing-ethereum-keys-for-peggo).  Place this key in the `keys/ethereum-peggo` directory.  NOTE: Delete the file `DELETE-ME` as its a placeholder

## CLI Usage

A CLI image containing the `injectived` binary is also available. For example:
- To display node status:
  ```bash
  docker compose run --rm cli tendermint show-node-id
  ```
- To query account balances:
  ```bash
  docker compose run --rm cli query bank balances <your_address> --node http://injective:26657/
  ```

## Version

Injective Node Docker uses semantic versioning.

This is Injective Node Docker v1.0.0
