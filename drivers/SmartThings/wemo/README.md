# Wemo integration documentation

The purpose of this readme is to document the behavior of various Wemo devices,
since during the development of the driver there have been some weird behavior.
The document will also explain any mitigations the driver makes to provide a
consistent integration despite the weird behavior.

## Device connectivity is sometimes fickle

**Device discovery and re-discovery on the LAN**

After being on the network for some period of time, some devices stop
responding to ssdp multicast requests. This is a problem for the driver since every time
a device is initialized due to a driver restart, migration, or newly discovered device,
the driver must try to discover the device on the LAN. The driver will try to discover
the device forever to get the most up to date IP address. This particularly impacts the migration
use case where devices backed by a DTH have been on the network for a long time. For such devices
that have an IP address but are not being re-discovered on the LAN, polling and a subscription will
be setup. Obviously connectivity issues may cause these actions to fail, making the device
non functional within SmartThings; however, these actions do frequently work even if the device
is not responding to discovery requests.

**Subscriptions sometimes fail on the device, sometimes regularly**

Since connectivity is somewhat fickle, occasionally subscriptions will stop working from the device. There is not a
way to detect that the subscription broke with the device prior to the timeout (1.5 hours), but subscriptions are
setup again every 1 hour. During the period of time when the subscription is not functional, the device state will
be collected via the polling mechanism. This will result in a user experience where the app will timeout prior to
the poll reporting the new state.

One device would never allow a subscription to be setup, and would fail with `412 Precondition Failed` errors.

We could follow a Set and then Get pattern for the capability handlers mitigate this bad user experience, but that would
result in unnecessary network traffic in most cases. Instead there is a mitigation in place where a device refresh
will result in re-subscribing to the device, since refreshing is a way users try to clarify device state when it doesn't
update fast enough.

## Wemo devices have two MAC addresses

Wemo devices have one MAC for the wifi access point they use when onboarding to the home network,
and they have another MAC that is 1 greater when connected to the home network.
Notice the `utils.mac_equals` function used in the discovery task, which will
consider a MAC search term discovered if we discover a device with a MAC that is one
off of the search term. This is necessary to support devices migrated from a DTH.
Devices coming from a DTH have their MAC as the MAC used on the home network, but
this information is not available to the driver socket, and the MAC reported by
the device is the other MAC used for the access point on the device. There is no
guarantee that all wemos do this, so we have to consider a device may report the
actual MAC. Note that when discovering new devices when compared with the devices on the

## Device testing notes

When a device is not being discovered on the LAN, often it just takes, unplugging and plugging
back in the device for it to be discovered.

The wall powered Wemo Motion Sensors were less likely to be discovered on the LAN from the driver with scan nearby,
or with a linux tool such as `gssdp-discover`. Only 1 of the 3 I tested were successfully discovered with gssdp on the
LAN. This indicates a device issue, although migrated devices
did have successful device communication during polling and subscriptions, and the devices responded to some ssdp
requests. This is very weird behavior, where devices aren't discoverable unless the driver initiates communication
other than SSDP with the devices.

The old Wemo Switches, and newer Mini Switch and Insight Switches worked fairly consistently with respect
to maintaining subscriptions and LAN connectivity. Although all did occasionally encounter situations where
the subscription was dropped by the device, or the device stopped responding to discovery requests. Usually just
sending a command or resubscribing to the device will fix the issues. One old switch never seemed to let a subscription
be setup on it.

No Wemo in wall switches were tested, and no devices with the Switch Level capability were tested.
