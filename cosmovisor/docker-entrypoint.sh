#!/usr/bin/env bash
set -euo pipefail

# Common cosmovisor paths.
__cosmovisor_path=/cosmos/cosmovisor
__genesis_path=$__cosmovisor_path/genesis
__current_path=$__cosmovisor_path/current
__upgrades_path=$__cosmovisor_path/upgrades

if [[ ! -f /cosmos/.initialized ]]; then
  echo "Initializing!"
  mkdir -p $__cosmovisor_path/tmp
  wget "${DOWNLOAD_BASE_URL}/${BINARY_TAG}/linux-amd64.zip" -O $__cosmovisor_path/tmp/linux-amd64.zip
  unzip -o $__cosmovisor_path/tmp/linux-amd64.zip -d $__genesis_path/bin/
  chmod +x $__genesis_path/bin/"$DAEMON_NAME"
  chmod +x $__genesis_path/bin/peggo


  mkdir -p $__upgrades_path/"$DAEMON_VERSION"/bin
  cp  $__genesis_path/bin/"$DAEMON_NAME" $__upgrades_path/"$DAEMON_VERSION"/bin/"$DAEMON_NAME"
  cp  $__genesis_path/bin/peggo $__upgrades_path/"$DAEMON_VERSION"/bin/peggo

  # Point to current.
  ln -s -f $__genesis_path $__current_path

  echo "Running init..."
  $__genesis_path/bin/"$DAEMON_NAME" init "$MONIKER" --chain-id "$NETWORK" --home /cosmos --overwrite

# Get specific genesis file based on network.
  echo "Downloading genesis..."
  if [ "${NETWORK}" = "injective-1" ]; then
    GENESIS_URL="https://raw.githubusercontent.com/InjectiveLabs/mainnet-config/refs/heads/master/10001/genesis.json"
  else
    GENESIS_URL="http://injective-snapshots.s3.amazonaws.com/testnet/genesis.json"
  fi

  wget $GENESIS_URL -O /cosmos/config/genesis.json

  if [ -n "$SNAPSHOT" ]; then
    echo "Downloading snapshot..."
    curl -o - -L "$SNAPSHOT" | lz4 -c -d - | tar --exclude='data/priv_validator_state.json' -x -C /cosmos
  else
    echo "No snapshot URL defined."
  fi

  # Check whether we should rapid state sync
  if [ -n "${STATE_SYNC_URL}" ]; then
    echo "Configuring rapid state sync"
    # Get the latest height
    LATEST=$(curl -s "${STATE_SYNC_URL}/block" | jq -r '.result.block.header.height')
    echo "LATEST=$LATEST"

    # Calculate the snapshot height
    SNAPSHOT_HEIGHT=$((LATEST - 2000));
    echo "SNAPSHOT_HEIGHT=$SNAPSHOT_HEIGHT"

    # Get the snapshot hash
    SNAPSHOT_HASH=$(curl -s "$STATE_SYNC_URL"/block\?height=$SNAPSHOT_HEIGHT | jq -r '.result.block_id.hash')
    echo "SNAPSHOT_HASH=$SNAPSHOT_HASH"

    dasel put -f /cosmos/config/config.toml -v true statesync.enable
    dasel put -f /cosmos/config/config.toml -v "${STATE_SYNC_URL},${STATE_SYNC_URL}" statesync.rpc_servers
    dasel put -f /cosmos/config/config.toml -v "$SNAPSHOT_HEIGHT" statesync.trust_height
    dasel put -f /cosmos/config/config.toml -v "$SNAPSHOT_HASH" statesync.trust_hash
  else
    echo "No rapid sync url defined."
  fi

  touch /cosmos/.initialized
  touch /cosmos/.cosmovisor
else
  echo "Already initialized!"
fi

# Handle updates and upgrades.
__should_update=0

compare_versions() {
    current=$1
    new=$2

    # Remove leading 'v' if present
    ver_current="${current#v}"
    ver_new="${new#v}"

    # Check if the versions match exactly
    if [ "$ver_current" = "$ver_new" ]; then
        __should_update=0  # Versions are the same
    else
        __should_update=1  # Versions are different
    fi
}

# First, we get the current version and compare it with the desired version.
__current_version=$($__current_path/bin/"$DAEMON_NAME" version | awk '/Version/ {print $2}')

echo "Current version: ${__current_version}. Desired version: ${DAEMON_VERSION}"

compare_versions "$__current_version" "$DAEMON_VERSION"

if [ "$__should_update" -eq 1 ]; then
  echo "Downloading new version and setting it as current"
  mkdir -p $__upgrades_path/"$DAEMON_VERSION"/bin

  wget "${DOWNLOAD_BASE_URL}/${BINARY_TAG}/linux-amd64.zip" -O $__upgrades_path/"$DAEMON_VERSION"/bin/linux-amd64.zip
  unzip -o $__upgrades_path/"$DAEMON_VERSION"/bin/linux-amd64.zip -d $__upgrades_path/"$DAEMON_VERSION"/bin/
  chmod +x $__upgrades_path/"$DAEMON_VERSION"/bin/"$DAEMON_NAME"
  chmod +x $__upgrades_path/"$DAEMON_VERSION"/bin/peggo
  rm -f $__current_path
  ln -s -f $__upgrades_path/"$DAEMON_VERSION" $__current_path
  echo "Done!"
else
  echo "No updates needed."
fi

echo "Updating config..."

# Get public IP address.
__public_ip=$(curl -s ifconfig.me/ip)
echo "Public ip: ${__public_ip}"

# Always update public IP address, moniker and ports.
dasel put -f /cosmos/config/config.toml -v "1s" consensus.timeout_commit
dasel put -f /cosmos/config/config.toml -v "${__public_ip}:${CL_P2P_PORT}" p2p.external_address
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_P2P_PORT}" p2p.laddr
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_RPC_PORT}" rpc.laddr
dasel put -f /cosmos/config/config.toml -v "$DB_BACKEND" db_backend
dasel put -f /cosmos/config/config.toml -v "$MONIKER" moniker
dasel put -f /cosmos/config/config.toml -v true -t bool prometheus
dasel put -f /cosmos/config/config.toml -v "$LOG_LEVEL" log_level
dasel put -f /cosmos/config/config.toml -v true -t bool instrumentation.prometheus
dasel put -f /cosmos/config/config.toml -v "$SEEDS" p2p.seeds
dasel put -f /cosmos/config/config.toml -v 25600000 p2p.recv_rate
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${RPC_PORT}" json-rpc.address
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${WS_PORT}" json-rpc.ws-address
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${CL_GRPC_PORT}" grpc.address
dasel put -f /cosmos/config/app.toml -v true -t bool grpc.enable
dasel put -f /cosmos/config/app.toml -v "$MIN_GAS_PRICE" "minimum-gas-prices"
dasel put -f /cosmos/config/app.toml -v 0 "iavl-cache-size"
dasel put -f /cosmos/config/app.toml -v true -t bool "iavl-disable-fastnode"
dasel put -f /cosmos/config/client.toml -v "tcp://localhost:${CL_RPC_PORT}" node
dasel put -f /cosmos/config/config.toml -v "1s" consensus.timeout_propose
dasel put -f /cosmos/config/config.toml -v "100ms" consensus.timeout_propose_delta
dasel put -f /cosmos/config/config.toml -v "250ms" consensus.timeout_prevote
dasel put -f /cosmos/config/config.toml -v "100ms" consensus.timeout_prevote_delta
dasel put -f /cosmos/config/config.toml -v "250ms" consensus.timeout_precommit
dasel put -f /cosmos/config/config.toml -v "100ms" consensus.timeout_precommit_delta
dasel put -f /cosmos/config/config.toml -v "500ms" consensus.timeout_commit
dasel put -f /cosmos/config/config.toml -v true -t bool storage.discard_abci_responses
dasel put -f /cosmos/config/config.toml -v "null" tx_index.indexer
dasel put -f /cosmos/config/config.toml -v 500 mempool.size
dasel put -f /cosmos/config/config.toml -v 1073741824 mempool.max_txs_bytes

# Update peers if set
if [ -n "${PEERS:-}" ]; then
  echo "Updating persistent peers..."
  dasel put -f /cosmos/config/config.toml -v "$PEERS" p2p.persistent_peers
fi


# cosmovisor will create a subprocess to handle upgrades
# so we need a special way to handle SIGTERM

# Start the process in a new session, so it gets its own process group.
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
setsid "$@" ${EXTRA_FLAGS} &
pid=$!

# Trap SIGTERM in the script and forward it to the process group
trap 'kill -TERM -$pid' TERM

# Wait for the background process to complete
wait $pid