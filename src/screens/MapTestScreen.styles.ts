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
  validationPanel: {
    position: 'absolute',
    left: 12,
    right: 12,
    bottom: 96,
    backgroundColor: 'rgba(15,23,42,0.85)',
    borderRadius: 12,
    paddingVertical: 8,
    paddingHorizontal: 8,
  },
  validationLabel: {
    color: '#E2E8F0',
    fontSize: 11,
    fontWeight: '700',
    marginBottom: 6,
    textAlign: 'center',
  },
  validationRow: {
    alignItems: 'center',
    paddingRight: 2,
  },
  validationButton: {
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 14,
    marginRight: 6,
    paddingVertical: 6,
    paddingHorizontal: 10,
  },
  validationButtonActive: {
    backgroundColor: '#0F766E',
  },
  validationButtonText: {
    color: '#CBD5E1',
    fontSize: 12,
    fontWeight: '600',
  },
  validationButtonTextActive: {
    color: '#FFFFFF',
  },
  zoomRow: {
    alignSelf: 'center',
    flexDirection: 'row',
    marginTop: 6,
  },
  zoomButton: {
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 12,
    marginHorizontal: 3,
    paddingVertical: 5,
    paddingHorizontal: 10,
  },
  zoomButtonActive: {
    backgroundColor: '#0F766E',
  },
  zoomButtonText: {
    color: '#CBD5E1',
    fontSize: 12,
    fontWeight: '600',
  },
  zoomButtonTextActive: {
    color: '#FFFFFF',
  },
});
