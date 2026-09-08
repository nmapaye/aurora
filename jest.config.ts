import type { Config } from 'jest';

const shared = {
  moduleNameMapper: {
    '^~/(.*)$': '<rootDir>/src/$1',
  },
};

const unitProject: Config = {
  displayName: 'unit',
  roots: ['<rootDir>/tests'],
  testMatch: ['**/?(*.)+(spec|test).+(ts|tsx|js)'],
  testPathIgnorePatterns: ['<rootDir>/tests/ui/'],
  transform: {
    '^.+\\.(ts|tsx)$': [
      'ts-jest',
      {
        tsconfig: {
          rootDir: '.',
          target: 'ES2020',
          module: 'commonjs',
          jsx: 'react-jsx',
          strict: true,
          esModuleInterop: true,
          skipLibCheck: true,
        },
      },
    ],
  },
  ...shared,
  testEnvironment: 'node',
  setupFilesAfterEnv: ['<rootDir>/tests/setup.ts'],
};

const uiProject: Config = {
  displayName: 'ui',
  preset: 'jest-expo',
  roots: ['<rootDir>/tests/ui'],
  testMatch: ['**/?(*.)+(spec|test).+(ts|tsx|js)'],
  ...shared,
  setupFilesAfterEnv: ['<rootDir>/tests/ui/setup.ts'],
  transformIgnorePatterns: [
    'node_modules/(?!((jest-)?react-native|@react-native(-community)?)|expo(nent)?|@expo(nent)?/.*|@react-navigation/.*|react-native-reanimated|react-native-worklets|react-native-svg|decode-uri-component)',
  ],
};

const config: Config = {
  projects: [unitProject, uiProject],
};

export default config;
