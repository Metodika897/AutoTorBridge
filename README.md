## AutoTorBridge

This project contains a script that automatically creates between 1 and 8 
Tor bridges on your Debian system.  

**Under the hood:**

* **Podman:** Used for managing Docker containers, providing a secure and 
efficient environment for running Tor bridge instances.
* **Nftables:** Configures a firewall to protect your bridge network and 
ensure only authorized traffic passes through.
* **Unattended Upgrades:** Keeps your system up-to-date with the latest 
security patches and bug fixes, ensuring optimal performance and 
reliability.

**Tested on Debian 12.**

**Usage:**

1.  Login to your server using SSH.
2.  Run the command `./command` (replace "command" ).
3.  Copy the provided configuration at the end of the script 
execution.
