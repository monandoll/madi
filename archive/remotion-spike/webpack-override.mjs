/**
 * TS NodeNext 스타일 `./x.js` 임포트를 webpack 이 .ts/.tsx 로 풀게 한다.
 * packages/shared 가 엔진(Node ESM)과 Remotion(webpack) 양쪽에서 같은 소스로 쓰이므로 필요하다.
 */
export const webpackOverride = (config) => ({
  ...config,
  resolve: {
    ...config.resolve,
    extensionAlias: {
      ...(config.resolve?.extensionAlias ?? {}),
      '.js': ['.ts', '.tsx', '.js'],
      '.mjs': ['.mts', '.mjs'],
    },
  },
});
