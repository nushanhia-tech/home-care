"use client";
import React, { useEffect } from "react";
import {
  MapContainer,
  TileLayer,
  Marker,
  Popup,
  useMap,
  useMapEvents,
} from "react-leaflet";
import L from "leaflet";
const pin = L.divIcon({
  className: "place-marker",
  html: "<span></span>",
  iconSize: [26, 26],
  iconAnchor: [13, 26],
});
const livePin = L.divIcon({
  className: "live-marker",
  html: "<span></span>",
  iconSize: [24, 24],
  iconAnchor: [12, 12],
});
function Events({ onChange }) {
  useMapEvents({
    click: (event) =>
      onChange?.({ latitude: event.latlng.lat, longitude: event.latlng.lng }),
  });
  return null;
}
function Center({ point, live, destination }) {
  const map = useMap();
  useEffect(() => {
    const points = [point, live, destination]
      .filter(Boolean)
      .map((p) => [p.latitude, p.longitude]);
    if (points.length > 1)
      map.fitBounds(points, { padding: [32, 32], maxZoom: 16, animate: false });
    else if (points.length)
      map.setView(points[0], Math.max(map.getZoom(), 14), { animate: false });
  }, [
    point?.latitude,
    point?.longitude,
    live?.latitude,
    live?.longitude,
    destination?.latitude,
    destination?.longitude,
    map,
  ]);
  return null;
}
export default function PlaceMap({ point, onChange, live, destination }) {
  const center = point ||
    live ||
    destination || { latitude: 10.805, longitude: 76.186 };
  return (
    <MapContainer
      center={[center.latitude, center.longitude]}
      zoom={point || live ? 15 : 11}
      scrollWheelZoom={false}
      zoomAnimation={false}
      fadeAnimation={false}
      markerZoomAnimation={false}
      className="place-map"
      aria-label="Location map"
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <Events onChange={onChange} />
      <Center point={point} live={live} destination={destination} />
      {point && (
        <Marker
          position={[point.latitude, point.longitude]}
          icon={pin}
          draggable={!!onChange}
          eventHandlers={{
            dragend: (e) => {
              const p = e.target.getLatLng();
              onChange?.({ latitude: p.lat, longitude: p.lng });
            },
          }}
        >
          <Popup>Service / pickup place</Popup>
        </Marker>
      )}
      {destination && (
        <Marker
          position={[destination.latitude, destination.longitude]}
          icon={pin}
        >
          <Popup>Destination</Popup>
        </Marker>
      )}
      {live && (
        <Marker position={[live.latitude, live.longitude]} icon={livePin}>
          <Popup>Provider GPS · accuracy ±{Math.round(live.accuracy)} m</Popup>
        </Marker>
      )}
    </MapContainer>
  );
}
