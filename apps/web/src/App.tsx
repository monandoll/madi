import { useEngineEvents } from './lib/ws.js';
import { useScreen } from './lib/route.js';
import { Gallery } from './screens/Gallery.js';
import { SettingsScreen } from './screens/Settings.js';

export function App() {
  useEngineEvents();
  const screen = useScreen();
  return screen === 'settings' ? <SettingsScreen /> : <Gallery />;
}
