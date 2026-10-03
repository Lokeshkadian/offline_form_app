const String defaultBaseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'http://10.0.2.2:3000',
);

const Duration requestTimeout = Duration(seconds: 15);
const Duration uploadTimeout = Duration(seconds: 30);

const Duration healthTimeout = Duration(seconds: 5);
