// Minimal Expo config plugin to enable HealthKit and add Info.plist messages
// Usage (app.json):
//   "plugins": [["./plugins/with-healthkit", { "shareMessage": "Reads sleep to tailor plans." }]]
const { withInfoPlist, withEntitlementsPlist, createRunOncePlugin } = require('@expo/config-plugins');

const pkg = { name: 'with-healthkit', version: '1.0.0' };

const withHealthKit = (config, props = {}) => {
  // Add Info.plist usage strings
  config = withInfoPlist(config, (c) => {
    const shareMsg = props.shareMessage || 'This app reads your sleep data to improve recommendations.';
    c.modResults.NSHealthShareUsageDescription = c.modResults.NSHealthShareUsageDescription || shareMsg;
    // Only set update usage if explicitly requested
    if (props.updateMessage) {
      c.modResults.NSHealthUpdateUsageDescription = props.updateMessage;
    }
    return c;
  });

  // Enable HealthKit capability via entitlements
  config = withEntitlementsPlist(config, (c) => {
    c.modResults['com.apple.developer.healthkit'] = true;
    return c;
  });

  return config;
};

module.exports = createRunOncePlugin(withHealthKit, pkg.name, pkg.version);

