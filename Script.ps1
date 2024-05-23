import os
import json
import requests
import shutil
from time import sleep
import taglib

# Paths and configuration
source_path = '/mnt/downloads/slskd/complete'
target_base_path = '/mnt/remote/usenet/Music'
holding_path = '/mnt/downloads/slskd/complete'
log_path = '/mnt/opt/scripts/lidarr/slskd/music-organizer-log.txt'

lidarr_host = "http://lidarr:8686"
api_key = "Your_API_Key"
headers = {"X-Api-Key": api_key}

extensions = ['mp3', 'wav', 'aac', 'flac', 'm4a', 'alac', 'ogg', 'wma', 'aif', 'aiff', 'ape', 'dsf', 'dff', 'midi', 'mid', 'opus']

def write_log(message):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    with open(log_path, 'a') as log_file:
        log_file.write(f"[{timestamp}] {message}\n")

def lookup_artist_id(artist_name):
    encoded_artist_name = requests.utils.quote(artist_name)
    response = requests.get(f"{lidarr_host}/api/v1/artist/lookup?term={encoded_artist_name}", headers=headers)
    if response.status_code == 200 and response.json():
        artist_id = response.json()[0]['id']
        write_log(f"Artist ID found for '{artist_name}': {artist_id}")
        return artist_id
    else:
        write_log(f"No artist found with the name '{artist_name}'.")
        return None

def retag_files(artist_id):
    uri = f"{lidarr_host}/api/v1/retag?artistId={artist_id}"
    response = requests.get(uri, headers=headers)
    for item in response.json():
        path = item['path']
        file = taglib.File(path)
        for change in item['changes']:
            property_name = change['field'].replace(' ', '')
            new_value = change['newValue']
            if property_name.lower() in file.tags:
                file.tags[property_name.lower()] = [new_value]
        parent_directory = os.path.dirname(artist_path)
        genre = os.path.basename(parent_directory)
        file.tags['genre'] = [genre]
        file.save()
        write_log(f"Successfully updated tags for file: {path}")

def process_files(artist_id):
    uri = f"{lidarr_host}/api/v1/rename?artistId={artist_id}"
    response = requests.get(uri, headers=headers)
    for item in response.json():
        existing_path = item['existingPath']
        new_path = item['newPath']
        new_dir = os.path.dirname(new_path)
        if not os.path.exists(new_dir):
            os.makedirs(new_dir)
            write_log(f"Created directory: {new_dir}")
        shutil.move(existing_path, new_path)
        write_log(f"Successfully moved and renamed file to: {new_path}")

def trigger_lidarr_rescan(path):
    body = json.dumps({
        "name": "RescanFolders",
        "folders": [path]
    })
    response = requests.post(f"{lidarr_host}/api/v1/command", headers=headers, data=body)
    command_id = response.json()['id']
    while True:
        sleep(5)
        command_status_response = requests.get(f"{lidarr_host}/api/v1/command/{command_id}", headers=headers)
        if command_status_response.json()['status'] == "completed":
            break
    write_log(f"Lidarr rescan completed for {path}")

def main():
    dry_run = False
    files = [os.path.join(dp, f) for dp, dn, filenames in os.walk(source_path) for f in filenames if f.split('.')[-1] in extensions]
    grouped_files = {}
    for file_path in files:
        artist = taglib.File(file_path).tags.get('ARTIST', [None])[0]
        if artist not in grouped_files:
            grouped_files[artist] = []
        grouped_files[artist].append(file_path)

    for artist, file_paths in grouped_files.items():
        artist_directory = None
        for root, dirs, _ in os.walk(target_base_path):
            if artist in dirs:
                artist_directory = os.path.join(root, artist)
                break

        is_in_holding_path = False
        if not artist_directory:
            artist_directory = os.path.join(holding_path, artist)
            is_in_holding_path = True
            if not dry_run:
                os.makedirs(artist_directory, exist_ok=True)
            write_log(f"Fallback created artist directory: {artist_directory}")

        for file_path in file_paths:
            try:
                tag_file = taglib.File(file_path)
                album = tag_file.tags.get('ALBUM', [None])[0]
                if not album:
                    write_log(f"Skipping file due to missing album tag: {file_path}")
                    continue

                album_directory = os.path.join(artist_directory, album)
                if not os.path.exists(album_directory):
                    if not dry_run:
                        os.makedirs(album_directory, exist_ok=True)
                    write_log(f"Created album directory: {album_directory}")

                destination = os.path.join(album_directory, os.path.basename(file_path))
                if not dry_run:
                    shutil.move(file_path, destination)
                    write_log(f"Moved file from {file_path} to {destination}")

            except Exception as e:
                write_log(f"Error processing file {file_path}: {e}")

        trigger_lidarr_rescan(artist_directory)

        artist_id = lookup_artist_id(artist)
        if artist_id:
            process_files(artist_id)
            retag_files(artist_id)
            trigger_lidarr_rescan(artist_directory)

    write_log("Operation completed.")

if __name__ == "__main__":
    main()
