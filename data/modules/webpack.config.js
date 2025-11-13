const path = require('path');

module.exports = {
  mode: 'production',
  entry: './build/main.js',
  output: {
    path: path.resolve(__dirname, 'build'),
    filename: 'main.js',
  },
  target: 'node',
  resolve: {
    extensions: ['.js'],
  },
  externals: {
    'minio': 'commonjs minio',
  },
};




