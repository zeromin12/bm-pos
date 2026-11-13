import type { Metadata, Viewport } from 'next';
import './globals.css';
export const metadata:Metadata={title:'BM POS — Kasir & Manajemen Usaha',description:'Kasir praktis, bisnis terkendali.',manifest:'/manifest.webmanifest',icons:{icon:'/icon.svg',apple:'/icon.svg'}};
export const viewport:Viewport={width:'device-width',initialScale:1,themeColor:'#172c48'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="id"><body>{children}</body></html>}
