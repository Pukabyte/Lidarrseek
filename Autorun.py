import time
import json
import subprocess

config_path = 'F:\\Windows Files\\Program Files\\Scripts\\Soulseek to Lidarr\\AutoRunFrequency.json'
script_path = 'F:\\Windows Files\\Program Files\\Scripts\\Soulseek to Lidarr\\script.py'

def load_config(config_path):
    with open(config_path, 'r') as file:
        config = json.load(file)
    return config

def run_script(script_path):
    subprocess.run(['python', script_path], check=True)

def main():
    while True:
        config = load_config(config_path)
        frequency_minutes = config.get('frequencyMinutes', 0.5)
        run_script(script_path)
        time.sleep(frequency_minutes * 60)

if __name__ == "__main__":
    main()
