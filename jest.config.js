const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    moduleNameMapper: {
        // sfdx-lwc-jest ships no stub for lightning/actions, used by quick-action components.
        '^lightning/actions$': '<rootDir>/force-app/test/jest-mocks/lightning/actions'
    }
};
