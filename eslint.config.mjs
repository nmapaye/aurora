import globals from 'globals';
import tseslint from 'typescript-eslint';
import reactPlugin from 'eslint-plugin-react';

export default [
  // Global ignores
  { ignores: ['**/node_modules/**','**/ios/**','**/android/**','**/dist/**','**/.expo/**'] },

  // JavaScript files
  {
    files: ['**/*.{js,mjs,cjs,jsx}'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: { ...globals.browser, ...globals.node },
    },
    plugins: { react: reactPlugin },
    rules: {
      'react/react-in-jsx-scope': 'off',
      'react/prop-types': 'off'
    },
    settings: { react: { version: 'detect' } },
  },

  // TypeScript files
  ...tseslint.configs.recommended,
  {
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      parserOptions: {
        project: false,
        tsconfigRootDir: import.meta.dirname,
      },
      globals: { ...globals.browser, ...globals.node },
    },
    plugins: { react: reactPlugin },
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      '@typescript-eslint/no-require-imports': 'off'
    },
    settings: { react: { version: 'detect' } },
  },

  // File-specific overrides
  { files: ['metro.config.js'], rules: { '@typescript-eslint/no-require-imports': 'off' } },
];