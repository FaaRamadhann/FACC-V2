package com.faa.facc;

import java.io.BufferedReader;
import java.io.InputStreamReader;

/**
 * RootShell — eksekusi perintah root via {@code su -c}.
 * Dipakai FACC Manager untuk memanggil CLI module:
 * {@code su -c "facc --scan --json"} dkk.
 */
public class RootShell {

    public static class Result {
        public String out = "";
        public String err = "";
        public int code = -1;
        public boolean timedOut = false;
    }

    /** Cek apakah perangkat punya akses root (su tersedia & granted). */
    public static boolean hasRoot() {
        try {
            Result r = exec("echo facc-root-ok", 8000);
            return r != null && r.code == 0 && r.out.contains("facc-root-ok");
        } catch (Exception e) {
            return false;
        }
    }

    /** Cek apakah CLI module FACC (facc2/v1) terpasang & bisa jalan. */
    public static boolean hasFacc() {
        try {
            Result r = exec("facc --version", 10000);
            return r != null && r.code == 0 && r.out.contains("FACC");
        } catch (Exception e) {
            return false;
        }
    }

    /** Jalankan perintah shell sebagai root. */
    public static Result exec(String cmd, int timeoutMs) {
        Result res = new Result();
        Process p = null;
        try {
            p = Runtime.getRuntime().exec(new String[]{"su", "-c", cmd});
            long end = System.currentTimeMillis() + Math.max(timeoutMs, 1000);
            boolean done = false;
            while (System.currentTimeMillis() < end) {
                try {
                    p.exitValue();
                    done = true;
                    break;
                } catch (IllegalThreadStateException itse) {
                    try {
                        Thread.sleep(100);
                    } catch (InterruptedException ie) {
                        break;
                    }
                }
            }
            if (!done) {
                res.timedOut = true;
                try {
                    p.destroy();
                } catch (Exception ignored) {
                }
                return res;
            }
            res.code = p.exitValue();
            res.out = readAll(p, false);
            res.err = readAll(p, true);
        } catch (Exception e) {
            res.err = String.valueOf(e.getMessage());
        } finally {
            if (p != null) {
                try {
                    p.destroy();
                } catch (Exception ignored) {
                }
            }
        }
        return res;
    }

    private static String readAll(Process p, boolean error) {
        StringBuilder sb = new StringBuilder();
        BufferedReader br = null;
        try {
            br = new BufferedReader(new InputStreamReader(
                    error ? p.getErrorStream() : p.getInputStream(), "UTF-8"));
            char[] buf = new char[4096];
            int n;
            while ((n = br.read(buf)) != -1) {
                sb.append(buf, 0, n);
            }
        } catch (Exception ignored) {
        } finally {
            if (br != null) {
                try {
                    br.close();
                } catch (Exception ignored) {
                }
            }
        }
        return sb.toString().trim();
    }
}
