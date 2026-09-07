# Single-stage on purpose.
#
# The bundle is HTML/CSS/JS — byte-identical on any architecture — so there is
# nothing to gain from compiling it inside the image, and a multi-stage
# cross-platform build could not be exported in this environment at all. The
# bundle is produced by scripts/deploy-gke.sh (or `npm run build`) before the
# image is built, and only the nginx layer is architecture-specific.
#
# Because the RUM credentials are inlined into the bundle at build time, they
# are passed to `npm run build` as VITE_* environment variables, not here.
FROM nginx:1.27

COPY dist/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
