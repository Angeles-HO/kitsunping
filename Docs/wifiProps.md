# WiFi Properties MANUAL.md

## Description

This document serves as a reference for various WiFi-related properties that Kitsunping may interact with, modify, or monitor. It is designed to help users and developers understand which properties are relevant to WiFi performance and how they can be utilized within the context of Kitsunping's functionality.

Some properties are straightforward to use, while others may require specific conditions to be effective. This guide aims to simplify the complex landscape of WiFi properties on Android devices.

---

## Common `init.svc.*` Properties

- **[init.svc.bpfloader]: [stopped]**  
  BPF Loader Service: Manages the loading of Berkeley Packet Filter, a framework for kernel-level packet filtering.
- **[init.svc.mdnsd_netbpfload]: [stopped]**  
  mDNS with BPF Service: Multicast DNS with BPF filtering capabilities for networks.
- **[init.svc.netd]: [running]**  
  Network Daemon: Main manager for Android system network connectivity.
- **[init.svc.netdagent]: [running]**  
  Netd Agent: Assists in managing network policies and configurations.
- **[init.svc.wificond]: [running]**  
  WiFi Controller: Daemon for managing WiFi interfaces.
- **[init.svc.wlan_assistant]: [running]**  
  WLAN Assistant: Auxiliary service for managing wireless networks.

---

## Common Logging Properties

- **[log.tag.ClatdController]: [D]**  
  Log Level for ClatdController: Debugging for the IPv6-to-IPv4 transition controller.
- **[log.tag.ConnectivityManager]: [D]**  
  Log Level for ConnectivityManager: Debugging for the connectivity manager.
- **[log.tag.ConnectivityService]: [D]**  
  Log Level for ConnectivityService: Debugging for the connectivity service.
- **[log.tag.IptablesRestoreController]: [D]**  
  Log Level for Iptables: Debugging for the iptables rules restorer.
- **[persist.log.tag.PowerHalWifiMonitor]: [I]**  
  Persistent Log for PowerHal: Information about the WiFi power monitor.
- **[persist.log.tag.RtcPhb]: [I]**  
  Persistent Log for RTC/PHB: Information about the real-time clock/address book.

---

## Common Carrier and Network Properties

- **[mdc.sys.carrierid_etcpath]: [/prism/etc/carriers/single/ARO]**  
  Carrier Configuration Path: Directory for carrier-specific configurations.
- **[mdc.sys.omc_etcpath]: [/prism/etc/carriers/single/PSN]**  
  OMC Configuration Path: Operator Managed Configuration settings.
- **[persist.sys.omc_etcpath]: [/prism/etc/carriers/single/PSN]**  
  Persistent OMC Configuration Path: Persistent operator configuration settings.

---

## WiFi Configuration Properties

- **[mediatek.wlan.ctia]: [0]**  
  CTIA Test Mode: Disables WiFi certification test mode (0 = disabled).
- **[persist.sys.setupwizard.jig_on_wifisetup]: [0]**  
  WiFi Jig Configuration: Disables test device during WiFi setup.
- **[persist.sys.vzw_wifi_running]: [false]**  
  Verizon WiFi State: Indicates if Verizon WiFi network is active.
- **[persist.vendor.viwifi_support]: [1]**  
  ViWiFi Support: Enables virtual WiFi (1 = enabled).
- **[ro.mediatek.wlan.p2p]: [1]**  
  WiFi Direct Support: Enables peer-to-peer connections.
- **[ro.mediatek.wlan.wsc]: [1]**  
  WPS Support: Enables WiFi Protected Setup.
- **[ro.setupwizard.wifi_on_exit]: [false]**  
  WiFi State on Exit: WiFi disabled after setup completion.
- **[ro.vendor.wifi.sap.concurrent.iface]: [ap1]**  
  Concurrent AP Interface: Interface for simultaneous access points.
- **[ro.vendor.wifi.sap.interface]: [swlan0]**  
  SoftAP Interface: Interface for access point mode.
- **[ro.vendor.wlan.standalone.log]: [y]**  
  Standalone WLAN Log: Enables separate logging system for WiFi.
- **[ro.wifi.channels]: []**  
  Available WiFi Channels: Empty list indicates default regional channels.

---

## RIL Configuration

- **[ril.bip_dns_in_progress]: [1]**  
  DNS BIP in Progress: Indicates active DNS resolution for Bearer Independent Protocol.
- **[ril.data.intfprefix]: [rmnet]**  
  Data Interface Prefix: Prefix for mobile data interfaces (used in tethering).
- **[ril.signal.disprssi0]: [false]**  
  Antenna 0 Signal State: Indicates if the main antenna signal is suppressed.
- **[ril.support.incrementalscan]: [1]**  
  Incremental Scan: Enables progressive scanning of cellular networks.

---

## System Properties

- **[ro.fuse.bpf.is_running]: [false]**  
  FUSE BPF State: Indicates if the FUSE filesystem with BPF is active.
- **[ro.vendor.connsys.dedicated.log.port]: [bt,wifi,gps,mcu]**  
  Dedicated Log Ports: Ports for logging various subsystems.

---

## Technical Documentation for Related Properties

### TCP/IP Optimization
- **net.ipv4.allowed_congestion_control**: Lists allowed TCP congestion control algorithms.   
- **net.tcp.buffersize**: Configures buffer sizes for different connection types.
- **net.ipv4.tcp_congestion_control**: Congestion control algorithm (recommended: `bbr`).
- **net.ipv4.tcp_window_scaling**: Allows TCP windows >64KB.
- **net.ipv4.tcp_sack**: Selective acknowledgments.

### RIL and Mobile Data Optimization

- **ro.ril.hsxpa**: Configures HSPA/HSPA+ support (1-3).
- **ro.ril.hsdpa.category**: HSDPA category (8, 10, 28).
- **ro.ril.hsupa.category**: HSUPA category (5, 6, 9).
- **ro.ril.gprsclass**: GPRS/EDGE class (10, 12).
- **ro.ril.disable.power.collapse**: Modem power-saving control.
- **ro.ril.set.mtusize**: MTU configuration for cellular networks.

### IPv6 Configuration

- **persist.telephony.support.ipv6**: Enables native IPv6 support.
- **persist.telephony.support.ipv4**: Maintains IPv4 compatibility.

### Manufacturer Optimizations

- **Qualcomm**: `persist.vendor.data.mode`, `persist.vendor.data.iwlan.enable`.
- **MediaTek**: `ro.vendor.mtk_nn.support`, `vendor.audio.adm.buffering.ms`.

### General Configurations

- **ro.telephony.default_network**: Default network configuration.
- **ro.config.hw_fast_dormancy**: Improves energy efficiency.

### Advanced WiFi (WiFi 7/MLO)

- **STR/MLO**: Simultaneous Transmit and Receive / Multi-Link Operation.
- **WiFi 7 Configurations**: Link aggregation, dynamic selection, puncturing.

---

## Qualcomm-Specific WiFi Properties

- **[persist.vendor.wifi.enable]: [true]**  
  Enables WiFi functionality on Qualcomm devices.
- **[ro.vendor.wifi.hardware]: [qcom]**  
  Specifies Qualcomm as the WiFi hardware provider.
- **[persist.vendor.wifi.country_code]: [US]**  
  Sets the default country code for WiFi operation.
- **[ro.vendor.wifi.firmware]: [WCNSS_qcom_cfg]**  
  Indicates the firmware configuration file for Qualcomm WiFi.
- **[persist.vendor.wifi.debug]: [1]**  
  Enables debugging for Qualcomm WiFi modules.
- **[ro.vendor.wifi.mac]: [XX:XX:XX:XX:XX:XX]**  
  Default MAC address for Qualcomm WiFi interfaces.
- **[persist.vendor.wifi.scan_interval]: [15]**   
  Sets the scan interval for WiFi networks in seconds.
- **[ro.vendor.wifi.tx_power]: [20]**  
  Configures the transmission power level for Qualcomm WiFi.
- **[persist.vendor.wifi.roaming]: [enabled]**  
  Enables WiFi roaming on Qualcomm devices.
- **[ro.vendor.wifi.channels]: [1,6,11]**  
  Specifies the default WiFi channels for Qualcomm hardware.

---

## system.prop Configuration Additions



#### Radio / RIL
- **ro.ril.enable.dtm**: Improves multitasking by allowing simultaneous voice and data usage.
- **ro.ril.enable.a51, a52, a53, a54, a55**: Enhances security by enabling various encryption standards for GSM/GPRS traffic.
- **ro.ril.gprsclass**: Determines the data transfer class for GPRS, impacting speed and efficiency.
- **ro.ril.transmitpower**: Optimizes signal strength by managing transmission power.

#### Default Network Configuration
- **ro.telephony.default_network**: Configures the preferred network type for better connectivity.

#### Wi-Fi
- **ro.wifi.direct.interface**: Specifies the interface for peer-to-peer WiFi connections.

#### VoLTE / VoWiFi
- **persist.vendor.mtk.volte.enable**: Activates VoLTE for high-quality voice calls over LTE.
- **persist.vendor.volte_support**: Ensures compatibility with VoLTE networks.

#### Default Network Configuration
- **ro.telephony.default_network**: Configures the preferred network type for better connectivity.

#### Wi-Fi
- **ro.wifi.direct.interface**: Specifies the interface for peer-to-peer WiFi connections.

#### VoLTE / VoWiFi
- **persist.vendor.mtk.volte.enable**: Activates VoLTE for high-quality voice calls over LTE.
- **persist.vendor.volte_support**: Ensures compatibility with VoLTE networks.
- **persist.vendor.vowifi.enable**: Enables WiFi calling for improved indoor coverage.
- **persist.vendor.vowifi_support**: Ensures compatibility with WiFi calling features.

#### Energy and Miscellaneous
- **persist.sys.vzw_wifi_running**: Indicates the operational state of Verizon WiFi.
- **persist.radio.add_power_save**: Prevents additional power-saving measures that may impact performance.
- **ro.config.hw_power_saving**: Disables hardware-level power-saving to maintain performance.
- **persist.audio.fluence.voicecall**: Enhances voice call clarity using Fluence technology.
- **logcat.live**: Reduces resource usage by disabling live logging.

---

## Summary Table of Key Optimization Properties

| Property                          | Recommended Value       | Category       | Purpose                          |
|-----------------------------------|-------------------------|----------------|----------------------------------|
| wifi.supplicant_scan_interval     | 180                     | WiFi           | Battery saving                   |
| net.tcp.buffersize.wifi           | 524288,1048576...       | TCP            | Maximum throughput               |
| net.ipv4.tcp_congestion_control   | bbr                     | TCP            | Latency reduction                |
| persist.telephony.support.ipv6    | 1                       | IP             | Dual-stack connectivity          |
| ro.ril.hsxpa                      | 3                       | RIL            | Maximum HSPA+ speed              |
| ro.config.hw_fast_dormancy        | 1                       | RIL            | Energy efficiency                |
| net.dns1                          | 8.8.8.8                 | Network        | Fast DNS                         |
| persist.vendor.data.mode          | concurrent              | Qualcomm       | Smooth handover                  |
| ro.ril.set.mtusize                | 1420                    | IP             | MTU alignment                    |
| ro.telephony.call_ring.delay      | 0                       | Telephony      | No call delay                    |

> **Note**: Optimization properties listed in the documentation section are not present in the original `getprop` file but are included as technical references.