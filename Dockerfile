# CPU/MPI FUNWAVE-TVD image used by the daily GitHub Actions forecast.
# Pin FUNWAVE_REF to a commit SHA once the first build is proven.
FROM ubuntu:24.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG FUNWAVE_REF=b4c322e7582035ee19df8e6409a3dfedaff1cb96

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git make gfortran openmpi-bin libopenmpi-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone https://github.com/fengyanshi/FUNWAVE-TVD.git funwave-src && \
    cd funwave-src && git checkout "${FUNWAVE_REF}" && \
    # AB_OUTPUT writes Ax, Ay, Bx and By required by the vertical-profile diagnostic.
    make COMPILER=gnu PARALLEL=true MPI=openmpi EXEC=funwave FLAG_12=-DAB_OUTPUT && \
    install -D -m 0755 funwave /opt/funwave/bin/funwave

FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openmpi-bin python3 r-base pandoc \
    r-cran-ggplot2 r-cran-jsonlite r-cran-knitr r-cran-ncdf4 r-cran-rmarkdown r-cran-terra && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/funwave/bin/funwave /opt/funwave/bin/funwave
COPY --from=builder /opt/funwave-src/simple_cases/beach_2d_radiation /opt/funwave-test-case

ENV PATH="/opt/funwave/bin:${PATH}"
WORKDIR /work
ENTRYPOINT ["/bin/bash"]
