FROM ghcr.io/flatpak/gnome-sdk:49

# O SDK já contém GTK4, libadwaita e todas as libs necessárias.
# Instalamos apenas ferramentas adicionais que o SDK pode não ter.
RUN apt-get update && apt-get install -y \
    wget \
    desktop-file-utils \
    file \
    gettext \
    && rm -rf /var/lib/apt/lists/*

# Não é mais necessário instalar ou compilar GTK4 ou libadwaita

WORKDIR /work
