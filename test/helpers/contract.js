const { MockProvider } = require('ethereum-waffle');

let provider;

module.exports = {
	getProvider: () => {
		if (provider == undefined) {
			provider = new MockProvider();
		}
		return provider;
	}
};
