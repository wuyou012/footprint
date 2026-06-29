import { StatusBar } from 'expo-status-bar';
import { useState, type ReactNode } from 'react';

import { DayDetailScreen } from './src/screens/DayDetailScreen';
import { HistoryScreen } from './src/screens/HistoryScreen';
import { RecordScreen } from './src/screens/RecordScreen';

type Route =
  | { name: 'record' }
  | { name: 'history' }
  | { name: 'dayDetail'; dayKey: string };

export default function App() {
  const [route, setRoute] = useState<Route>({ name: 'record' });

  let screen: ReactNode;
  if (route.name === 'history') {
    screen = (
      <HistoryScreen
        onBack={() => setRoute({ name: 'record' })}
        onSelectDay={(dayKey) => setRoute({ name: 'dayDetail', dayKey })}
      />
    );
  } else if (route.name === 'dayDetail') {
    screen = (
      <DayDetailScreen
        dayKey={route.dayKey}
        onBack={() => setRoute({ name: 'history' })}
        onDeleted={() => setRoute({ name: 'history' })}
      />
    );
  } else {
    screen = <RecordScreen onOpenHistory={() => setRoute({ name: 'history' })} />;
  }

  return (
    <>
      {screen}
      <StatusBar style="auto" />
    </>
  );
}
