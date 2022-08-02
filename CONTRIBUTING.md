# Contributing to SmartThingsEdgeDrivers

> We are only accepting pull requests for Works With SmartThings (WWST) Certification requests, or for bug fixes to existing drivers. For more info on WWST certification, visit our [certification documentation](https://developer-preview.smartthings.com/docs/certification/overview).

Want to contribute? Great! First, read this page. By submitting a pull request, you represent that you have the right to
license your contribution to SmartThings and agree by submitting the patch that
your contributions are licensed under the [Apache 2.0 license](LICENSE). Before
submitting your pull request, please make sure you have tested your changes and that
they follow the project guidelines for contributing code.

Before contributions can be merged, all contributors must agree to the [SmartThings
Individual Contributor License
Agreement](https://cla-assistant.io/SmartThingsCommunity/SmartThingsEdgeDrivers).

## To Submit an Edge Driver and Request WWST Certification:

> If you have feature requests for SmartThings Edge Drivers or have questions, please contact us at build@smartthings.com

1. Fork the SmartThingsEdgeDrivers repository and modify the desired base SmartThings Edge Driver to include your devices. A few things to keep in mind:
    * The most efficient way to complete WWST Certification for a driver is to limit your changes to only adding your product information and device fingerprint.
    * Custom capabilities and custom preferences are not supported.
    * More substantial changes (such as sub-drivers) require unit testing and may be subject to additional review during WWST Certification testing.
2. Submit a pull request containing your changes against this repository.
3. After submitting a pull request, visit the [SmartThings Console](https://developer-preview.smartthings.com/console) to continue the certification process.
    * Please do not make any changes to your pull request after submitting a certification request, unless under the guidance of a SmartThings employee. 
    * In the Console, provide us with information about your device. Include the URL for your pull request.
    * After you submit your certification request, we will follow up with additional guidance.
4. Once Certification is complete, your pull request will be merged.
