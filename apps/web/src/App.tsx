import { useEngineEvents } from './lib/ws.js';
import { useRoute } from './lib/route.js';
import { Gallery } from './screens/Gallery.js';
import { OutputDetail } from './screens/OutputDetail.js';
import { SettingsScreen } from './screens/Settings.js';
import { VideoDetail } from './screens/VideoDetail.js';

export function App() {
  useEngineEvents();
  const route = useRoute();
  switch (route.screen) {
    case 'settings':
      return <SettingsScreen />;
    case 'video':
      return <VideoDetail id={route.id} />;
    case 'output':
      return <OutputDetail id={route.id} />;
    default:
      return <Gallery />;
  }
}
