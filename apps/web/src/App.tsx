import { useEngineEvents } from './lib/ws.js';
import { Gallery } from './screens/Gallery.js';

export function App() {
  useEngineEvents();
  return <Gallery />;
}
