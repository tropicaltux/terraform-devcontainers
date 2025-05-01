#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import logging
import argparse

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

def get_token_from_aws_ssm(name_prefix, devcontainer_id):
    """
    Get the OpenVSCode server token for a specific devcontainer from AWS SSM Parameter Store.
    
    Args:
        devcontainer_id: The ID of the devcontainer to get the token for
        name_prefix: The name prefix for the parameter
        
    Returns:
        The token as a string
    """
    try:
        # Use the naming pattern /{name_prefix}/devcontainers/{devcontainer_id}/openvscode-token
        parameter_name = f"/{name_prefix}/devcontainers/{devcontainer_id}/openvscode-token"
        
        result = subprocess.run(
            ["aws", "ssm", "get-parameter", 
             "--name", parameter_name, 
             "--with-decryption", 
             "--query", "Parameter.Value", 
             "--output", "text"],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        logging.error(f"Failed to retrieve token for devcontainer {devcontainer_id} from AWS SSM Parameter Store: {e}")
        logging.error(f"Error output: {e.stderr}")
        sys.exit(1)


def try_get_container_specific_ssh_key(name_prefix, container_id):
    """
    Try to get container-specific SSH key if it exists.
    
    Args:
        name_prefix: The name prefix for the parameter
        container_id: The ID of the container
        
    Returns:
        The SSH key as a string or None if it doesn't exist
    """
    container_ssh_key_param = f"/{name_prefix}/devcontainers/{container_id}/ssh-public-key"
    try:
        result = subprocess.run(
            ["aws", "ssm", "get-parameter", 
             "--name", container_ssh_key_param, 
             "--with-decryption", 
             "--query", "Parameter.Value", 
             "--output", "text"],
            capture_output=True,
            text=True,
            check=True
        )
        key = result.stdout.strip()
        if key:
            logging.info(f"Found container-specific SSH key for {container_id}")
            return key
        return None
    except subprocess.CalledProcessError:
        # Parameter doesn't exist, which is expected for containers without specific keys
        return None


def main():
    """
    Read the devcontainers.json configuration file and run the devcontainer_up_with_web_ui.sh script.
    """
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Run devcontainers based on configuration')
    parser.add_argument('--name-prefix', required=True, help='Name prefix for the parameters')
    parser.add_argument('--public-ip', required=True, help='EC2 instance public IPv4 address.')
    parser.add_argument('--scripts-dir', required=True, help='Path to the scripts directory')
    parser.add_argument('--config', required=True, help='Path to the devcontainers configuration file')

    args = parser.parse_args()
    
    name_prefix = args.name_prefix
    public_ip = args.public_ip
    scripts_dir = args.scripts_dir
    devcontainers_config = args.config
    
    # Set SCRIPTS environment variable for child processes
    os.environ['SCRIPTS'] = scripts_dir
    
    # Check if the devcontainer_up_with_web_ui.sh script exists
    devcontainer_script = os.path.join(scripts_dir, 'devcontainer_up_with_web_ui.sh')
    if not os.path.isfile(devcontainer_script):
        logging.error(f"Devcontainer script not found at {devcontainer_script}")
        sys.exit(1)
    
    # Check if the devcontainers.json file exists
    if not os.path.isfile(devcontainers_config):
        logging.error(f"Devcontainers configuration file not found at {devcontainers_config}")
        sys.exit(1)
    
    # Read the devcontainers.json file
    try:
        with open(devcontainers_config, 'r') as f:
            devcontainers = json.load(f)
        
        if not isinstance(devcontainers, list):
            logging.error("The devcontainers configuration is not a list")
            sys.exit(1)
        
        logging.info(f"Found {len(devcontainers)} devcontainer(s) in the configuration")
            
        # Process each devcontainer
        for devcontainer in devcontainers:
            devcontainer_id = devcontainer['id']
            repo_url = devcontainer['source']
            branch = devcontainer.get('branch', '')
            devcontainer_path = devcontainer.get('devcontainer_path', '')
            port = devcontainer.get('port', 8000)
            
            logging.info(f"Processing devcontainer: {devcontainer_id} from {repo_url} on port {port}")
            
            # Get the token for this specific devcontainer
            token = get_token_from_aws_ssm(name_prefix, devcontainer_id)
            
            # Set environment variables for the script
            env = os.environ.copy()
            env['DEVCONTAINER_ID'] = devcontainer_id
            env['REPO_URL'] = repo_url
            env['OPENVSCODE_TOKEN'] = token
            env['PUBLIC_IP'] = public_ip
            
            if branch:
                env['BRANCH'] = branch
                
            if devcontainer_path:
                env['DEVCONTAINER_PATH'] = devcontainer_path

            remote_access = devcontainer.get('remote_access', {})

            # Check if OpenVSCode Server is configured and pass OpenVSCode Server configuration
            openvscode_server_config = remote_access.get('openvscode_server', {})
            env['OPENVSCODE_SERVER_ENABLED'] = 'true' if openvscode_server_config else 'false'
            if openvscode_server_config:
                env['OPENVSCODE_SERVER_PORT'] = str(openvscode_server_config.get('port', 8000))

            # Check if SSH is configured and pass SSH configuration
            ssh_config = remote_access.get('ssh', {})
            env['SSH_ENABLED'] = 'true' if ssh_config else 'false'
            
            # Set SSH public key if available - try container-specific key first, then global key
            if ssh_config:
                # Try to get container-specific SSH key
                container_ssh_key = try_get_container_specific_ssh_key(name_prefix, devcontainer_id)
                
                if container_ssh_key:
                    env['SSH_PUBLIC_KEY'] = container_ssh_key
                    env['SSH_PORT'] = str(ssh_config.get('port'))
                    logging.info(f"Using container-specific SSH key for {devcontainer_id} on port {env['SSH_PORT']}")
                else:
                    raise Exception(f"No SSH key available for {devcontainer_id}.")
            
            # Run the script for this devcontainer
            logging.info(f"Running devcontainer_up_with_web_ui.sh for {devcontainer_id}")
            result = subprocess.run(
                [devcontainer_script],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            if result.returncode != 0:
                logging.error(f"devcontainer_up_with_web_ui.sh failed for {devcontainer_id} with error code {result.returncode}")
                logging.error(f"Error: {result.stderr}")
                sys.exit(result.returncode)
            
            logging.info(f"Output for {devcontainer_id}:\n{result.stdout}")
        
        logging.info("All devcontainers have been successfully set up")
        
    except json.JSONDecodeError as e:
        logging.error(f"Failed to parse devcontainers.json: {e}")
        sys.exit(1)
    except Exception as e:
        logging.error(f"An error occurred: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 