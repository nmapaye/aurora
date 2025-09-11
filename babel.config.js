module.exports = function(api){
  api.cache(true);
  return {
    presets: ['babel-preset-expo'],
    plugins: [
      ['module-resolver', { root: ['./'], alias: { '~': './src' } }],
      // Reanimated v4 moved its Babel plugin to react-native-worklets
      'react-native-worklets/plugin'
    ]
  };
};
  
