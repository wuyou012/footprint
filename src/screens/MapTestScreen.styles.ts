import { StyleSheet } from 'react-native';

export const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F8FAFC',
  },
  map: {
    flex: 1,
  },
  badge: {
    position: 'absolute',
    top: 56,
    alignSelf: 'center',
    backgroundColor: 'rgba(15,23,42,0.85)',
    borderRadius: 16,
    paddingVertical: 6,
    paddingHorizontal: 14,
  },
  badgeText: {
    color: '#FFFFFF',
    fontSize: 13,
    fontWeight: '600',
  },
  controls: {
    position: 'absolute',
    bottom: 40,
    alignSelf: 'center',
    flexDirection: 'row',
    backgroundColor: 'rgba(15,23,42,0.85)',
    borderRadius: 24,
    padding: 4,
  },
  button: {
    paddingVertical: 8,
    paddingHorizontal: 18,
    borderRadius: 20,
  },
  buttonActive: {
    backgroundColor: '#0F766E',
  },
  buttonText: {
    color: '#CBD5E1',
    fontSize: 13,
    fontWeight: '600',
  },
  buttonTextActive: {
    color: '#FFFFFF',
  },
});
