'use client';
export default function ErrorPage({reset}:{reset:()=>void}){return <main className="section-shell content-page"><h1>Let’s give that another try.</h1><p>We couldn’t load this page. Your bookings are still safely stored.</p><button className="button" onClick={reset}>Try again</button></main>;}
