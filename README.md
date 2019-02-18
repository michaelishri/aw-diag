# AirWatch Diagnostics Tool
The AirWatch Diagnostics Tool is your friend. It collects information about your AirWatch server and presents it to you on a single screen.
This can come in really handy in large environments with many servers. It can help you find and correlate issues across multiple servers simply by comparing them.

_Note: The script presents information about the server it's run on. It does not reach out to other servers to collect information about them._

## What can it do?
So far, it can:
- Collect basic information about your AirWatch installation
- Collect basic information about your AirWatch Cloud Messenger installation
- Parse your Host file
- Show information about relevant installed software
- Poll the AirWatch message queues
- Report on AirWatch Windows services

![aw-diag-sample](https://user-images.githubusercontent.com/11097710/52927681-9dfe8d80-33a0-11e9-8ee9-a11b20a500b1.png)

## Requirements
The script requires PowerShell 6 to run.

## Installation
You simply need to download and copy `aw-diag.ps1` to your server.

## Usage
Once you have it copied to your server, you just need to run the script, it does the rest.

```
# Open PowerShell 6 (pwsh)
# Navigate to the folder where you copied the script.
# Run the script
PS > ./aw-diag.ps1
```

### Command Line Switches
By default, the script will poll your Windows services and Microsoft Message queues every two seconds.
- You can change poll frequency by using the `-PollIntervalSec` switch when calling the script.
- You can completely disable the automatic polling by using the `-DontPoll` switch. This will run the script once, then quit.

```
# Disable the Automatic Polling (run once)
PS > ./aw-diag.ps1 -DontPoll

# Change the Poll frequency to every 5 seconds
PS > ./aw-diag.ps1 -PollIntervalSec 5
```

## Final Note
This script is a work in progress, but please feel free to make suggestions for features.
