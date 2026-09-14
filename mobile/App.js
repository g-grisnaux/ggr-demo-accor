// The ALL mobile app, reduced to what a Mobile RUM demo actually needs: a real
// booking journey, a real network call into the BFF, a real crash.
//
// Deliberately not a polished product. Every screen exists to produce one kind
// of telemetry the architect asked about when talking about replacing Firebase.

import React, { useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  SafeAreaView,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { DdRum, DdSdkReactNative } from '@datadog/mobile-react-native';

import { DatadogProvider, config } from './src/datadog';
import { graphql, SEARCH_HOTELS, CREATE_BOOKING } from './src/api';

function isoDaysFromNow(days) {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

const CITIES = ['Paris', 'Lyon', 'Nice', 'London', 'Amsterdam'];

function Journey() {
  const [results, setResults] = useState(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null);
  const [crash, setCrash] = useState(false);

  // The deliberate crash. Reading a property of an undefined rate object is the
  // shape of bug that actually breaks booking funnels: the API changed and the
  // client was not updated. With native crash reporting on, this reaches
  // Datadog with a symbolicated stack.
  if (crash) {
    const rate = undefined;
    return <Text>{rate.totalPrice.amount}</Text>;
  }

  const city = CITIES[Math.floor(Math.random() * CITIES.length)];
  const checkIn = isoDaysFromNow(7);
  const checkOut = isoDaysFromNow(10);

  async function search() {
    setBusy(true);
    setMessage(null);
    // A named RUM view per step, so the funnel is readable in Datadog rather
    // than one undifferentiated session.
    await DdRum.startView('search', 'SearchScreen', {}, Date.now());
    try {
      const data = await graphql('SearchHotels', SEARCH_HOTELS, { city, checkIn, checkOut });
      setResults(data.searchHotels);
      await DdRum.addAction('hotel_search', 'search', {
        city,
        result_count: data.searchHotels.resultCount,
      }, Date.now());
    } catch (err) {
      setMessage(`${err.code || 'ERREUR'} — ${err.message}`);
    } finally {
      setBusy(false);
    }
  }

  async function book(hotel, offer) {
    setBusy(true);
    setMessage(null);
    await DdRum.startView('booking', 'BookingScreen', {}, Date.now());
    try {
      const data = await graphql('CreateBooking', CREATE_BOOKING, {
        input: {
          hotelId: hotel.id,
          guestId: 'mobile-demo-guest',
          checkIn,
          checkOut,
          guests: 2,
          rateCode: offer.rateCode,
          paymentMethod: 'VISA',
        },
      });
      setMessage(`Réservation ${data.createBooking.reference} confirmée`);
      await DdRum.addAction('booking_confirmed', 'book', {
        reference: data.createBooking.reference,
        total_price: data.createBooking.totalPrice,
      }, Date.now());
    } catch (err) {
      setMessage(`${err.code || 'ERREUR'} — ${err.message}`);
    } finally {
      setBusy(false);
    }
  }

  const bookable = (results?.hotels || []).filter(
    (h) => h.availability?.available && h.availability.offers.length
  );

  return (
    <SafeAreaView style={styles.screen}>
      <StatusBar barStyle="light-content" />
      <View style={styles.header}>
        <Text style={styles.headerText}>ALL · Réserver un séjour</Text>
      </View>

      <ScrollView contentContainerStyle={styles.body}>
        <Text style={styles.label}>
          {city} · {checkIn} → {checkOut}
        </Text>

        <Pressable style={styles.primary} onPress={search} disabled={busy}>
          <Text style={styles.primaryText}>{busy ? 'Recherche…' : 'Rechercher'}</Text>
        </Pressable>

        {busy && <ActivityIndicator style={styles.spinner} />}

        {message && (
          <View style={styles.notice}>
            <Text style={styles.noticeText}>{message}</Text>
          </View>
        )}

        {results && (
          <Text style={styles.label}>
            {results.resultCount} propriétés · {results.nights} nuits
          </Text>
        )}

        {bookable.slice(0, 6).map((hotel) => (
          <View key={hotel.id} style={styles.card}>
            <Text style={styles.cardTitle}>{hotel.name}</Text>
            <Text style={styles.cardMeta}>
              {hotel.brand} · {hotel.starRating}★ · {hotel.availability.roomsLeft} restantes
            </Text>
            {hotel.availability.offers.slice(0, 2).map((offer) => (
              <Pressable
                key={offer.rateCode}
                style={styles.secondary}
                onPress={() => book(hotel, offer)}
                disabled={busy}
              >
                <Text style={styles.secondaryText}>
                  {offer.rateCode} — {offer.totalPrice} {offer.currency}
                </Text>
              </Pressable>
            ))}
          </View>
        ))}

        <Pressable style={styles.danger} onPress={() => setCrash(true)}>
          <Text style={styles.dangerText}>Casser le tunnel (crash volontaire)</Text>
        </Pressable>
      </ScrollView>
    </SafeAreaView>
  );
}

export default function App() {
  React.useEffect(() => {
    // No real authentication here; a stable identity is enough for the session
    // and funnel views to be attributable.
    DdSdkReactNative.setUser({
      id: 'mobile-demo-guest',
      name: 'ALL demo guest',
    });
  }, []);

  return (
    <DatadogProvider configuration={config}>
      <Journey />
    </DatadogProvider>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#f2f2f5' },
  header: { backgroundColor: '#16325c', paddingVertical: 16, paddingHorizontal: 20 },
  headerText: { color: '#fff', fontSize: 17, fontWeight: '600' },
  body: { padding: 20, gap: 12 },
  label: { fontSize: 13, color: '#555' },
  primary: { backgroundColor: '#16325c', paddingVertical: 14, borderRadius: 8, alignItems: 'center' },
  primaryText: { color: '#fff', fontWeight: '600' },
  secondary: { backgroundColor: '#e8edf5', paddingVertical: 10, borderRadius: 6, alignItems: 'center', marginTop: 6 },
  secondaryText: { color: '#16325c', fontWeight: '500' },
  danger: { borderColor: '#b23', borderWidth: 1, paddingVertical: 12, borderRadius: 8, alignItems: 'center', marginTop: 24 },
  dangerText: { color: '#b23', fontWeight: '500' },
  card: { backgroundColor: '#fff', borderRadius: 10, padding: 14 },
  cardTitle: { fontSize: 15, fontWeight: '600' },
  cardMeta: { fontSize: 12, color: '#666', marginTop: 2 },
  notice: { backgroundColor: '#fff6e0', borderRadius: 8, padding: 12 },
  noticeText: { fontSize: 13, color: '#7a5200' },
  spinner: { marginTop: 8 },
});
