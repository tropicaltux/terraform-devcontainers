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

def main():
    """
    Read the devcontainers.json configuration file and run the devcontainer_up_with_web_ui.sh script.
    """
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Run devcontainers based on configuration')
    parser.add_argument('--scripts-dir', required=True, help='Path to the scripts directory')
    parser.add_argument('--config', required=True, help='Path to the devcontainers configuration file')
    args = parser.parse_args()
    
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
        for container in devcontainers:
            container_id = container['id']
            repo_url = container['source']
            branch = container.get('branch', '')
            devcontainer_path = container.get('devcontainer_path', '')
            port = container.get('port', 8000)
            
            logging.info(f"Processing devcontainer: {container_id} from {repo_url} on port {port}")
            
            # Set environment variables for the script
            env = os.environ.copy()
            env['DEVCONTAINER_ID'] = container_id
            env['REPO_URL'] = repo_url
            env['PORT'] = str(port)
            
            if branch:
                env['BRANCH'] = branch
                
            if devcontainer_path:
                env['DEVCONTAINER_PATH'] = devcontainer_path
            
            # Run the script for this devcontainer
            logging.info(f"Running devcontainer_up_with_web_ui.sh for {container_id}")
            result = subprocess.run(
                [devcontainer_script],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            if result.returncode != 0:
                logging.error(f"devcontainer_up_with_web_ui.sh failed for {container_id} with error code {result.returncode}")
                logging.error(f"Error: {result.stderr}")
                sys.exit(result.returncode)
            
            logging.info(f"Output for {container_id}:\n{result.stdout}")
        
        logging.info("All devcontainers have been successfully set up")
        
    except json.JSONDecodeError as e:
        logging.error(f"Failed to parse devcontainers.json: {e}")
        sys.exit(1)
    except Exception as e:
        logging.error(f"An error occurred: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 