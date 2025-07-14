#!/usr/bin/env bash
set -euo pipefail

# Initialization for graceful shutdown
STOPPED=false
REQUIRED_VARS=("MONIKER" "NETWORK" "CL_P2P_PORT" "CL_RPC_PORT")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "Error: Environment variable $var is not set!" >&2
    exit 1
  fi
done

# Trap SIGTERM and SIGINT so the script can exit quickly if requested.
# Adjust the pkill command to target injectived.
trap 'STOPPED=true; echo "Stopping services..."; pkill -SIGTERM injectived' SIGTERM SIGINT

if [[ ! -f /cosmos/.initialized ]]; then
  echo "Initializing!"

  echo "Running init..."
  injectived init "$MONIKER" --chain-id "$NETWORK" --home /cosmos --overwrite

  echo "Downloading genesis..."
  wget https://raw.githubusercontent.com/InjectiveLabs/mainnet-config/refs/heads/master/10001/genesis.json -O /cosmos/config/genesis.json

  echo "Downloading seeds..."
  SEEDS="seeds= "38c18461209694e1f667ff2c8636ba827cc01c86@176.9.143.252:11751,4f9025feca44211eddc26cd983372114947b2e85@176.9.140.49:11751,c98bb1b889ddb58b46e4ad3726c1382d37cd5609@65.109.51.80:11751,23d0eea9bb42316ff5ea2f8b4cd8475ef3f35209@65.109.36.70:11751,f9ae40fb4a37b63bea573cc0509b4a63baa1a37a@15.235.114.80:11751,7f3473ddab10322b63789acb4ac58647929111ba@15.235.13.116:11751,ade4d8bc8cbe014af6ebdf3cb7b1e9ad36f412c0@seeds.polkachu.com:14356,ebc272824924ea1a27ea3183dd0b9ba713494f83@injective-mainnet-seed.autostake.com:26726,1846e76e14913124a07e231586d487a0636c0296@tenderseed.ccvalidators.com:26007""
  dasel put -f /cosmos/config/config.toml -v "$SEEDS" p2p.seeds

  # If a stop signal was received, exit early.
  [[ "$STOPPED" == "true" ]] && { echo "Shutdown signal received, exiting early"; exit 0; }

  if [ -n "${SNAPSHOT:-}" ]; then
    echo "Downloading snapshot with aria2c..."

    # Download the snapshot using high concurrency.
    aria2c -x5 -s5 -j1 --allow-overwrite=true --console-log-level=notice --summary-interval=5 -d /cosmos -o snapshot.lz4 "$SNAPSHOT"


    if [ ! -f "/cosmos/snapshot.lz4" ]; then
      echo "Error: Snapshot file not found after download!"
      exit 1
    fi

    echo "Extracting snapshot..."
    # Determine the size of the snapshot file for progress tracking.
    SNAPSHOT_SIZE=$(stat -c %s /cosmos/snapshot.lz4)
    # Use pv to show extraction progress while decompressing with lz4 and extracting via tar.
    pv -s "$SNAPSHOT_SIZE" /cosmos/snapshot.lz4 | lz4 -c -d - | tar --exclude='data/priv_validator_state.json' -x -C /cosmos

    echo "Snapshot successfully extracted!"
    rm -f /cosmos/snapshot.lz4  # Clean up the snapshot file

    [[ "$STOPPED" == "true" ]] && { echo "Shutdown signal received during snapshot extraction, exiting early"; exit 0; }
  else
    echo "No snapshot URL defined."
  fi

  touch /cosmos/.initialized
else
  echo "Already initialized!"
fi

echo "Updating config..."

# Get public IP address, with fallbacks.
__public_ip=$(curl -s ifconfig.me || curl -s http://checkip.amazonaws.com || echo "UNKNOWN")
[[ "$STOPPED" == "true" ]] && { echo "Shutdown signal received before updating config, exiting early"; exit 0; }
echo "Public ip: ${__public_ip}"

# Update various configuration parameters.
dasel put -f /cosmos/config/config.toml -v "10s" consensus.timeout_commit
dasel put -f /cosmos/config/config.toml -v "${__public_ip}:${CL_P2P_PORT}" p2p.external_address
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_P2P_PORT}" p2p.laddr
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_RPC_PORT}" rpc.laddr
dasel put -f /cosmos/config/config.toml -v "$MONIKER" moniker
dasel put -f /cosmos/config/config.toml -v true prometheus
dasel put -f /cosmos/config/config.toml -v "$LOG_LEVEL" log_level
dasel put -f /cosmos/config/config.toml -v true instrumentation.prometheus
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${RPC_PORT}" json-rpc.address
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${WS_PORT}" json-rpc.ws-address
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${CL_GRPC_PORT}" grpc.address
dasel put -f /cosmos/config/app.toml -v true grpc.enable
dasel put -f /cosmos/config/app.toml -v "$MIN_GAS_PRICE" "minimum-gas-prices"
dasel put -f /cosmos/config/app.toml -v 0 "iavl-cache-size"
dasel put -f /cosmos/config/app.toml -v "true" "iavl-disable-fastnode"
dasel put -f /cosmos/config/app.toml -v "signet" "btc-config.network"
dasel put -f /cosmos/config/client.toml -v "tcp://localhost:${CL_RPC_PORT}" node

# Word splitting is desired for the command line parameters.
# shellcheck disable=SC2086
exec "$@" ${EXTRA_FLAGS}
