# Local Whisper Server Setup

Run a Whisper speech-to-text server on your Mac so the Forever Diary app can offload transcription over your local network. No API keys or internet required.

## Install (Homebrew)

```bash
brew install whisper-cpp
```

## Download Model

```bash
# large-v3-turbo (~1.5 GB) — best accuracy for Tagalog/multilingual
curl -L -o ~/ggml-large-v3-turbo.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
```

Other model options (smaller = faster, less accurate):

| Model | Size | Command |
|-------|------|---------|
| large-v3-turbo | ~1.5 GB | `curl -L -o ~/ggml-large-v3-turbo.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin` |
| medium | ~1.5 GB | `curl -L -o ~/ggml-medium.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin` |
| small | ~466 MB | `curl -L -o ~/ggml-small.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin` |
| base | ~142 MB | `curl -L -o ~/ggml-base.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin` |

## Run the Server

```bash
whisper-server -m ~/ggml-large-v3-turbo.bin --port 8080 --host 0.0.0.0
```

The `--host 0.0.0.0` flag makes the server accessible from other devices on your network (e.g., your iPhone). The server starts on `http://localhost:8080` and uses the whisper.cpp `/inference` API.

## Configure the App

1. Open **Settings** > **Speech**
2. Select **Server** as the engine
3. Set **Server URL** to `http://<your-mac-ip>:8080` (e.g., `http://192.168.1.5:8080`)
4. Tap **Test** to verify connectivity

To find your Mac's local IP:

```bash
ipconfig getifaddr en0
```

## Verify It Works

Test from the command line:

```bash
# Check server is running
curl http://localhost:8080/v1/models

# Test transcription with a WAV file
curl http://localhost:8080/v1/audio/transcriptions \
  -F "file=@test.wav" \
  -F "model=whisper-1" \
  -F "language=en"
```

## Run on Startup (Optional)

Create a launch agent to start the server automatically:

```bash
cat > ~/Library/LaunchAgents/com.whisper.server.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.whisper.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/whisper-server</string>
        <string>-m</string>
        <string>/Users/YOUR_USERNAME/ggml-large-v3-turbo.bin</string>
        <string>--port</string>
        <string>8080</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

# Replace YOUR_USERNAME, then load it
launchctl load ~/Library/LaunchAgents/com.whisper.server.plist
```

## Security Note

Audio recordings are sent over plaintext HTTP to your local server. This is fine on a trusted home/office network, but avoid using this on public Wi-Fi or untrusted networks where traffic could be intercepted.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| App says "Server unreachable" | Check your Mac's IP hasn't changed. Make sure both devices are on the same Wi-Fi. |
| App says "Not a Whisper server" | The URL is reachable but it's not a whisper.cpp server. Double-check the port and that whisper-server is running. |
| Slow transcription | Try a smaller model (medium or small). |
| Port already in use | Change `--port 8080` to another port and update the app's Server URL. |
| iPhone can't reach localhost | `localhost` only works on the same machine. Use your Mac's IP address instead. |
