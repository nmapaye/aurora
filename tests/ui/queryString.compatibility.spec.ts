const queryString = require('query-string');

describe('patched navigation query parser', () => {
  it('retains Unicode, spaces and repeated query parameters', () => {
    expect(queryString.parse('name=Jos%C3%A9+Smith&tag=a&tag=b&empty='))
      .toEqual({ name: 'José Smith', tag: ['a', 'b'], empty: '' });
    const params = { name: 'café', value: 'a+b' };
    expect(queryString.parse(queryString.stringify(params))).toEqual(params);
  });

  it('handles malformed percent sequences without losing valid text', () => {
    expect(queryString.parse('value=hello%20world%GG').value).toBe('hello world%GG');
    expect(typeof queryString.parse(`value=${'%FF'.repeat(1024)}`).value).toBe('string');
  });
});
