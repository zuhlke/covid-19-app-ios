# Notes about this fork

This is a fork of the [open source repo](https://github.com/nihp-public/covid-19-app-ios-ag-public) for the NHS COVID-19 iOS app.

## Why the fork?

The official repository has a few minor compilation issues in the open source version as some resources (e.g. to include URLs and other configuration).

This repo resolves those issues. All you need is the right version of Xcode (mentioned below) and you can test and run all targets for the simulator.

## Where to start?

Here are a few notes to help you get started.

* Due to a bug in Xcode 14, Swift Package Managers don’t resolve correctly when openning a fresh project. If you get an error after openning the project, just close the project and re-open it. The dependencies then should resolve correctly.
* `ExposureNotification` framework does not run on the simulator, so if you run the main (`NHS-COVID-19`) app you may be disappointed. Instead, select `NHS-COVID-19-Internal` scheme.
* The internal (or “Scenarios”) app is like an app-selector. When it launches, you can see various scenarios to choose from. If you’re just browsing the app functionality, the Mock environment scenario is a good place to start.
* After selecting a scenario, the app remembers your choice, even after a re-launch. This is to make the app behave like the production app as much as possible. If you want to return to the scenarios list, press and hold on the app icon and select “Reset Scenario”.
* Press and holding app icon also gives you other handy options, like access to a view to see logs or configure the mock endpoint.

## Disclaimer

The aim of this repository is to help with exploring the codebase and understanding how it functions.

This fork is not associated with the UK Department of Health and Social Care or any other government organisation. You can not install this fork of the app on your phone to detect exposures to COVID-19, and it is not a medical device. You must not use this as a source of medical advice or official government policy.

# NHS COVID-19 AG

An app using Apple’s [`ExposureNotification`](https://developer.apple.com/documentation/exposurenotification) API to detect contacts with other users of the app that may have had COVID-19.

## Dependencies

All dependencies are fetched using [Swift Package Manager](https://www.swift.org/package-manager/). Make sure you have access to the internal dependencies, and that git is properly configured to access these.

## Development

### Running the app on a simulator

The app requires Xcode 13.2+. You don't need to install anything else. Swift Package Manager will fetch dependencies when you open the project.

### Running the app on a device

This app requires entitlements that Xcode can not set up automatically. In order to run on a device:

* Ensure you are logged into the correct development team in Xcode.
* Ensure you have a development certificate and that your device is registered. Talk to a member of the team to learn about the latest policy around adding devices.
* Ask one of the technical App Managers to regenerate the provisioning profiles so it includes your device.
* Ask Xcode to download the latest profiles (Preferences > Accounts > Download Manual Profiles).

You should then be able to build and run on a device.

## Documentation

* [App Architecture](Docs/AppArchitecture.md) provides high level description of how the code is structured.
* [CI Workflows](Docs/CI.md) documents how we use GitHub Actions.
* [Development Guides](Docs/Development/Guides)
  * [PRs](Docs/Development/Guides/PRs.md) documents our approach to raising and reviewing PRs.
  * [Using `Domain`](Docs/Development/Guides/UsingDomain.md) is a good starting point for learning how the app’s backend works. 
