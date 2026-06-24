import { registerRootComponent } from 'expo';

import './src/services/BackgroundLocation';
import App from './App';

// registerRootComponent calls AppRegistry.registerComponent('main', () => App).
// Importing BackgroundLocation above registers the headless task before the app
// is mounted, which is required for Expo TaskManager background execution.
registerRootComponent(App);
