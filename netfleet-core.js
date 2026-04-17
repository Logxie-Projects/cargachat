    // ================================================================
    // SUPABASE — AUTH
    // ================================================================
    const SUPABASE_URL = 'https://pzouapqnvllaaqnmnlbs.supabase.co';
    const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB6b3VhcHFudmxsYWFxbm1ubGJzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU1MzYwMTksImV4cCI6MjA5MTExMjAxOX0.lj6Hx3sr9K8afvX5cDDE0pZJx5OfI1twVC9VJ1JieaU';
    const sb           = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

    let usuarioActual = null;
    let perfilActual  = null;
    let tokenActual   = null;

    // ── ESTADO GLOBAL DE ROL ──────────────────────────────────────
    let rolActivo = localStorage.getItem('netfleet_rol') || null;
    let tickerRolAplicado = false; // evitar doble replace en ticker

    function setRol(rol) {
      rolActivo = rol;
      localStorage.setItem('netfleet_rol', rol);
      tickerRolAplicado = false;
      document.querySelectorAll('.bifurcacion-card').forEach(c => c.classList.remove('activa'));
      document.getElementById('card-' + rol)?.classList.add('activa');
      aplicarRol();
      // Cambio 4 — título dinámico en #viajes
      const viajesTitles = {
        generador:    { title: 'Así se ven las cargas en la red de transportadores', sub: 'Precios reales · Pujas en tiempo real · Sin intermediarios' },
        transportador:{ title: 'Viajes disponibles ahora para tu flota',                  sub: 'Carga real · Pago garantizado · Tú pones el precio' }
      };
      const titleEl = document.getElementById('viajes-titulo');
      const subEl   = document.getElementById('viajes-subtitle');
      if (titleEl && viajesTitles[rol]) titleEl.textContent = viajesTitles[rol].title;
      if (subEl   && viajesTitles[rol]) subEl.textContent   = viajesTitles[rol].sub;
      // Cambio 5d — precios condicionales en mapa hero
      const priceEl = document.getElementById('hero-card-price');
      const badgeEl = document.getElementById('hero-card-badge');
      if (priceEl && badgeEl) {
        if (rol === 'generador') { priceEl.style.display = 'none'; badgeEl.textContent = '🏆 con ofertas activas'; }
        else if (rol === 'transportador') { priceEl.style.display = 'block'; badgeEl.textContent = '⚡ en subasta ahora'; }
      }
    }

    function aplicarRol() {
      if (!rolActivo) return;
      document.body.setAttribute('data-rol', rolActivo);
      actualizarSeccionesRol();
      actualizarTickerRol();
    }

    function actualizarSeccionesRol() {
      const seccionViajes   = document.getElementById('viajes');
      const seccionRetornos = document.getElementById('retornos-section');
      const titulo          = document.getElementById('viajes-titulo');
      const subtitulo       = document.getElementById('viajes-subtitle');
      const grid            = document.getElementById('viajes-grid');

      if (seccionRetornos) seccionRetornos.style.display = 'none';

      if (rolActivo === 'generador') {
        // Mostrar sección pero con contexto de empresa
        if (seccionViajes) seccionViajes.style.display = '';
        if (titulo)   titulo.textContent   = 'Así se ven las cargas en la red de transportadores';
        if (subtitulo) subtitulo.textContent = 'Precios reales · Pujas en tiempo real · Sin intermediarios';

        // Ocultar botones de acción en tarjetas
        document.querySelectorAll('.viaje-actions, .btn-aceptar, .btn-oferta, button[onclick*="aceptar"], button[onclick*="oferta"]')
          .forEach(b => b.style.display = 'none');

        // Agregar banner si no existe ya
        if (grid && !document.getElementById('banner-generador')) {
          const banner = document.createElement('div');
          banner.id        = 'banner-generador';
          banner.className = 'banner-generador';
          banner.innerHTML = '👆 Los transportadores ven estas cargas y hacen sus ofertas — la tuya aparecería aquí';
          grid.parentNode.insertBefore(banner, grid);
        }

        // Mapa contextual generador
        const tituloMapa  = document.querySelector('.mapa-col .section-hdr h2');
        const subtitMapa  = document.querySelector('.mapa-col .section-hdr p');
        const ctaMapa     = document.getElementById('cta-mapa');
        if (tituloMapa)  tituloMapa.textContent  = 'Rutas activas en Colombia ahora mismo';
        if (subtitMapa)  subtitMapa.textContent   = 'Tu carga aparecería en este mapa, visible para toda la red certificada';
        if (ctaMapa) {
          ctaMapa.textContent = 'Cotiza tu ruta sin compromiso →';
          ctaMapa.href = '#calculadora';
          ctaMapa.insertAdjacentHTML('afterend', '<p class="cta-mapa-micro">Gratis · Sin registro · Ofertas en menos de 2 horas</p>');
        }

      } else if (rolActivo === 'transportador') {
        // Mostrar todo normal
        if (seccionViajes) seccionViajes.style.display = '';
        if (titulo)    titulo.textContent    = 'Viajes disponibles ahora';
        if (subtitulo) subtitulo.textContent = '';

        // Restaurar botones
        document.querySelectorAll('.viaje-actions, .btn-aceptar, .btn-oferta, button[onclick*="aceptar"], button[onclick*="oferta"]')
          .forEach(b => b.style.display = '');

        // Quitar banner si existe
        const banner = document.getElementById('banner-generador');
        if (banner) banner.remove();

        // Quitar microcopy del CTA si ya fue insertado
        document.querySelectorAll('.cta-mapa-micro').forEach(el => el.remove());

        // Mapa contextual transportador
        const tituloMapa = document.querySelector('.mapa-col .section-hdr h2');
        const subtitMapa = document.querySelector('.mapa-col .section-hdr p');
        const ctaMapa    = document.getElementById('cta-mapa');
        if (tituloMapa) tituloMapa.textContent = 'Viajes disponibles para ti hoy';
        if (subtitMapa) subtitMapa.textContent  = 'Haz clic en cualquier ruta para ver detalles y presentar tu oferta';
        if (ctaMapa) { ctaMapa.textContent = 'Ver todos los viajes →'; ctaMapa.href = '#viajes'; }
      }
    }

    function actualizarTickerRol() {
      if (tickerRolAplicado) return;
      tickerRolAplicado = true;
      const label = rolActivo === 'generador' ? 'mejor oferta' : 'flete base';
      document.querySelectorAll('.ticker-item').forEach(item => {
        item.innerHTML = item.innerHTML.replace(
          /(\$[\d.,]+[MKB])/g,
          `$1 <span class="ticker-label-rol">${label}</span>`
        );
      });
    }

    document.addEventListener('DOMContentLoaded', () => {
      if (rolActivo) {
        document.querySelectorAll('.bifurcacion-card').forEach(c => c.classList.remove('activa'));
        document.getElementById('card-' + rolActivo)?.classList.add('activa');
        aplicarRol();
      }
    });

    async function fetchPerfil(userId, token) {
      try {
        const r = await fetch(`${SUPABASE_URL}/rest/v1/perfiles?id=eq.${userId}&select=*`, {
          headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${token || SUPABASE_KEY}` }
        });
        const rows = await r.json();
        return rows[0] || null;
      } catch { return null; }
    }

    sb.auth.onAuthStateChange(async (event, session) => {
      if (session?.user) {
        usuarioActual = session.user;
        tokenActual   = session.access_token;
        perfilActual  = await fetchPerfil(session.user.id, session.access_token);
        actualizarNav(perfilActual);
      } else {
        usuarioActual = null;
        perfilActual  = null;
        tokenActual   = null;
        actualizarNav(null);
      }
    });

    function actualizarNav(perfil) {
      const btnArea  = document.getElementById('nav-auth-buttons');
      const userArea = document.getElementById('nav-user-info');
      if (!perfil) {
        btnArea.style.display  = 'flex';
        userArea.style.display = 'none';
        return;
      }
      btnArea.style.display  = 'none';
      userArea.style.display = 'flex';
      document.getElementById('nav-user-name').textContent = perfil.nombre || perfil.email;
      const badge = document.getElementById('nav-user-badge');
      badge.textContent = perfil.estado === 'aprobado' ? '✓ Activo' : '⏳ Pendiente';
      badge.className   = 'nav-user-badge' + (perfil.estado !== 'aprobado' ? ' pendiente' : '');
    }

    // ── Modal selector (empresa / transportadora) ───────────────────
    function abrirSelectorModal() {
      document.getElementById('selector-modal').classList.add('open');
    }
    function cerrarSelectorModal() {
      document.getElementById('selector-modal').classList.remove('open');
    }

    // ── Modal de autenticación ──────────────────────────────────────
    function abrirAuthModal(tab = 'login') {
      document.getElementById('auth-modal').classList.add('open');
      cambiarAuthTab(tab);
      limpiarMensajesAuth();
    }
    function cerrarAuthModal() {
      document.getElementById('auth-modal').classList.remove('open');
      limpiarMensajesAuth();
    }

    /* ── MODAL DE VINCULACIÓN ── */
    const VINCULACION = {
      empresa: {
        tag:   'acceso para empresas',
        title: 'Proceso de vinculación',
        intro: 'Para garantizar la seguridad de cada operación, verificamos tu empresa antes de activar tu cuenta en la red NETFLEET.',
        items: [
          'RUT y NIT vigente',
          'Cámara de comercio',
          'Datos de operación: rutas, volumen y tipo de carga',
          'Persona de contacto y cargo'
        ],
        waLabel: 'Iniciar proceso →',
        waMsg:   'Hola, quiero publicar mi carga en NETFLEET e iniciar el proceso de vinculación como empresa.'
      },
      transportador: {
        tag:   'certificación de empresas de transporte',
        title: 'Vincula tu flota',
        intro: 'Trabajamos con empresas de transporte que operan flotas propias o administradas. Verificamos el cumplimiento legal y operativo antes de activar tu cuenta.',
        items: [
          'Habilitación MinTransporte de la empresa',
          'Tarjetas de operación de la flota',
          'SOAT y revisiones técnico-mecánicas al día',
          'Pólizas de responsabilidad civil vigentes',
          'Historial de operaciones de la empresa'
        ],
        waLabel: 'Iniciar vinculación de flota →',
        waMsg:   'Hola, quiero vincular mi empresa de transporte en NETFLEET e iniciar el proceso de certificación.'
      }
    };

    function abrirVinculacionModal(tipo) {
      const cfg = VINCULACION[tipo];
      if (!cfg) return;
      document.getElementById('vinc-tag').textContent   = cfg.tag;
      document.getElementById('vinc-title').textContent = cfg.title;
      document.getElementById('vinc-intro').textContent = cfg.intro;
      document.getElementById('vinc-list').innerHTML    = cfg.items.map(i => `<li>${i}</li>`).join('');
      document.getElementById('vinc-wa-label').textContent = cfg.waLabel;
      document.getElementById('vinc-wa-btn').href =
        `https://wa.me/573214401975?text=${encodeURIComponent(cfg.waMsg)}`;
      document.getElementById('vinculacion-modal').classList.add('open');
    }

    function cerrarVinculacionModal() {
      document.getElementById('vinculacion-modal').classList.remove('open');
    }

    /* ── MODAL LEAD CALCULADORA ── */
    function abrirLeadModal() {
      document.getElementById('lead-form-state').style.display    = 'block';
      document.getElementById('lead-success-state').style.display = 'none';
      document.getElementById('lead-error').style.display         = 'none';
      document.getElementById('lead-modal').classList.add('open');
    }
    function cerrarLeadModal() {
      document.getElementById('lead-modal').classList.remove('open');
    }
    async function enviarLead() {
      const nombre   = document.getElementById('lead-nombre').value.trim();
      const whatsapp = document.getElementById('lead-whatsapp').value.trim();
      const sector   = document.getElementById('lead-sector').value;
      const volumen  = document.getElementById('lead-volumen').value;
      const errEl    = document.getElementById('lead-error');

      if (!nombre || !whatsapp || !volumen) {
        errEl.textContent = 'Por favor completa nombre, WhatsApp y volumen.';
        errEl.style.display = 'block';
        return;
      }
      errEl.style.display = 'none';

      try {
        const resp = await fetch(`${SUPABASE_URL}/rest/v1/leads`, {
          method: 'POST',
          headers: {
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${SUPABASE_KEY}`,
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal'
          },
          body: JSON.stringify({ nombre_empresa: nombre, whatsapp, sector, volumen, fuente: 'calculadora' })
        });
        if (!resp.ok) throw new Error('Error al guardar');
        document.getElementById('lead-form-state').style.display    = 'none';
        document.getElementById('lead-success-state').style.display = 'block';
        // Limpiar campos
        ['lead-nombre','lead-whatsapp'].forEach(id => document.getElementById(id).value = '');
        document.getElementById('lead-sector').value  = '';
        document.getElementById('lead-volumen').value  = '';
      } catch(e) {
        errEl.textContent = 'Error de conexión. Intenta de nuevo.';
        errEl.style.display = 'block';
      }
    }
    function cerrarModalOverlay(e) {
      if (e.target === document.getElementById('auth-modal')) cerrarAuthModal();
    }
    function cambiarAuthTab(tab) {
      document.getElementById('form-login').style.display    = tab === 'login'    ? 'block' : 'none';
      document.getElementById('form-registro').style.display = tab === 'registro' ? 'block' : 'none';
      document.getElementById('tab-login').classList.toggle('active',    tab === 'login');
      document.getElementById('tab-registro').classList.toggle('active', tab === 'registro');
      limpiarMensajesAuth();
    }
    function mostrarErrorAuth(msg) {
      const el = document.getElementById('auth-error');
      el.textContent = msg; el.style.display = 'block';
      document.getElementById('auth-success').style.display = 'none';
    }
    function mostrarSuccessAuth(msg) {
      const el = document.getElementById('auth-success');
      el.textContent = msg; el.style.display = 'block';
      document.getElementById('auth-error').style.display = 'none';
    }
    function limpiarMensajesAuth() {
      document.getElementById('auth-error').style.display   = 'none';
      document.getElementById('auth-success').style.display = 'none';
    }

    // ── Acciones de auth ───────────────────────────────────────────
    async function iniciarSesion() {
      const email    = document.getElementById('login-email').value.trim();
      const password = document.getElementById('login-password').value;
      if (!email || !password) return mostrarErrorAuth('Completa todos los campos.');
      try {
        const resp = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${SUPABASE_KEY}`
          },
          body: JSON.stringify({ email, password })
        });
        const data = await resp.json();
        if (!resp.ok) return mostrarErrorAuth(data.error_description || data.msg || data.message || 'Credenciales incorrectas.');
        usuarioActual = data.user;
        tokenActual   = data.access_token;
        perfilActual  = await fetchPerfil(data.user.id, data.access_token);
        sb.auth.setSession({ access_token: data.access_token, refresh_token: data.refresh_token });
        actualizarNav(perfilActual);
        cerrarAuthModal();
        showToast('¡Bienvenido!');
      } catch(e) {
        mostrarErrorAuth('Error de conexión. Intenta de nuevo.');
      }
    }

    async function registrarse() {
      const nombre   = document.getElementById('reg-nombre').value.trim();
      const empresa  = document.getElementById('reg-empresa').value.trim();
      const telefono = document.getElementById('reg-telefono').value.trim();
      const nit      = document.getElementById('reg-nit').value.trim();
      const tipo     = document.getElementById('reg-tipo').value;
      const email    = document.getElementById('reg-email').value.trim();
      const password = document.getElementById('reg-password').value;

      if (!nombre || !empresa || !telefono || !tipo || !email || !password)
        return mostrarErrorAuth('Completa todos los campos.');
      if (password.length < 8)
        return mostrarErrorAuth('La contraseña debe tener al menos 8 caracteres.');

      const { data, error } = await sb.auth.signUp({
        email, password,
        options: { data: { nombre, empresa, telefono, nit, tipo } }
      });
      if (error) return mostrarErrorAuth(error.message);
      if (!data.user || data.user.identities?.length === 0)
        return mostrarErrorAuth('Este email ya tiene una cuenta. Intentá ingresar.');

      mostrarSuccessAuth('¡Cuenta creada! Tu acceso está pendiente de aprobación. Te notificaremos por email.');
    }

    async function cerrarSesion() {
      await sb.auth.signOut();
      showToast('Sesión cerrada');
    }

    // ================================================================
    // CONFIGURACIÓN GLOBAL
    // ================================================================

    // URL del CSV público de Google Sheets (pestaña VIAJES_LANDING).
    // Google Sheets permite publicar una hoja como CSV para que cualquiera la lea.
    // Para actualizar: Archivo → Compartir → Publicar en la web → CSV
    const CSV_URL = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQ93JERt_-UJ7Zzb9tQQxS4hhyUfLi6WLAO-vnoAZQCPM3i55sK1VeyyVj5hmu17EXzucPcEvHosarD/pub?gid=1429690977&single=true&output=csv';

    // Google Maps API Key para geocoding de ciudades desconocidas
    const GMAPS_KEY = 'AIzaSyBSDer_Cdp3pNhZrebp6h5OWDfHQkWJifo';

    // ================================================================
    // SISTEMA DE OFERTAS — Supabase
    // ================================================================
    let ofertaViajeIdx = null;
    let ofertasCounts = {};   // { viaje_rt: count }
    let ofertasMinimo = {};   // { viaje_rt: min_precio }

    // Cargar conteo + mejor oferta de todos los viajes
    async function cargarConteosOfertas() {
      try {
        const r = await fetch(`${SUPABASE_URL}/rest/v1/ofertas?estado=eq.activa&select=viaje_rt,precio_oferta`, {
          headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
        });
        const rows = await r.json();
        if (!Array.isArray(rows)) return;

        ofertasCounts = {};
        ofertasMinimo = {};
        rows.forEach(row => {
          const rt = row.viaje_rt;
          ofertasCounts[rt] = (ofertasCounts[rt] || 0) + 1;
          const p = parseFloat(row.precio_oferta) || 0;
          if (p > 0) {
            ofertasMinimo[rt] = Math.min(ofertasMinimo[rt] ?? Infinity, p);
          }
        });

        // Actualizar badges en las tarjetas
        document.querySelectorAll('[data-ofertas-rt]').forEach(el => {
          const rt  = el.getAttribute('data-ofertas-rt');
          const cnt = ofertasCounts[rt] || 0;
          const min = ofertasMinimo[rt];
          if (cnt === 0) { el.innerHTML = ''; return; }
          const comp = cnt === 1 ? '1 empresa compitiendo' : `${cnt} empresas compitiendo`;
          el.innerHTML = `
            <div class="mob-box">
              <div class="mob-top">
                <span class="mob-dot"></span>
                <span class="mob-tag">subasta activa</span>
              </div>
              ${min ? `<div class="mob-precio">Mejor oferta: ${formatCOP(min)}</div>` : ''}
              <div class="mob-comp">${comp}</div>
            </div>`;
        });
      } catch (e) { /* silencioso */ }
    }

    function formatPrecioInput(input) {
      let val = input.value.replace(/\D/g, '');
      if (val) input.value = parseInt(val).toLocaleString('es-CO');
    }

    function abrirOfertaModal(idx, accion) {
      const v = viajesData[idx];
      const precioBase = estimarPrecio(v.km, v.peso_kg, (v.destino||'').split(',').length, v.destino, v.origen);
      ofertaViajeIdx = idx;

      const destinos = (v.destino || '').split(',').map(d => d.trim()).filter(Boolean);
      const destinoTexto = destinos.length > 1 ? `${destinos[0]} +${destinos.length - 1} destinos` : v.destino;

      document.getElementById('oferta-titulo').textContent = accion === 'aceptar' ? 'Aceptar precio' : 'Hacer oferta';
      document.getElementById('oferta-resumen').innerHTML = `
        <strong>${v.origen} → ${destinoTexto}</strong><br>
        ${formatPeso(v.peso_kg)} · ${v.fecha_cargue || 'Fecha por confirmar'}
        ${precioBase > 0 ? `<br>Precio base: <strong>${formatCOP(precioBase)}</strong>` : ''}
      `;

      const precioInput = document.getElementById('oferta-precio');
      if (accion === 'aceptar' && precioBase > 0) {
        precioInput.value = Math.round(precioBase).toLocaleString('es-CO');
      } else {
        precioInput.value = '';
      }
      document.getElementById('oferta-comentario').value = '';
      document.getElementById('oferta-error').style.display = 'none';
      document.getElementById('oferta-success').style.display = 'none';
      document.getElementById('oferta-btn').disabled = false;
      document.getElementById('oferta-btn').textContent = 'Enviar oferta →';
      document.getElementById('oferta-modal').classList.add('open');
      precioInput.focus();
    }

    function cerrarOfertaModal() {
      document.getElementById('oferta-modal').classList.remove('open');
      ofertaViajeIdx = null;
    }

    async function enviarOferta() {
      const errorEl = document.getElementById('oferta-error');
      const successEl = document.getElementById('oferta-success');
      const btn = document.getElementById('oferta-btn');
      errorEl.style.display = 'none';
      successEl.style.display = 'none';

      const precioRaw = document.getElementById('oferta-precio').value.replace(/\D/g, '');
      const precio = parseInt(precioRaw) || 0;
      const comentario = document.getElementById('oferta-comentario').value.trim();

      if (precio < 100000) {
        errorEl.textContent = 'El precio mínimo es $100.000';
        errorEl.style.display = 'block';
        return;
      }

      const v = viajesData[ofertaViajeIdx];
      const rt = v.rt_total;
      if (!rt) {
        errorEl.textContent = 'Este viaje no tiene identificador. Intenta con otro.';
        errorEl.style.display = 'block';
        return;
      }

      btn.disabled = true;
      btn.textContent = 'Enviando...';

      try {
        const r = await fetch(`${SUPABASE_URL}/rest/v1/ofertas`, {
          method: 'POST',
          headers: {
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${tokenActual}`,
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal'
          },
          body: JSON.stringify({
            viaje_rt: rt,
            usuario_id: usuarioActual.id,
            nombre: perfilActual?.nombre || '',
            empresa: perfilActual?.empresa || '',
            telefono: perfilActual?.telefono || '',
            precio_oferta: precio,
            comentario: comentario || null
          })
        });

        if (r.status === 409 || r.status === 23505) {
          errorEl.textContent = 'Ya tienes una oferta activa para este viaje.';
          errorEl.style.display = 'block';
          btn.disabled = false;
          btn.textContent = 'Enviar oferta →';
          return;
        }

        if (!r.ok) {
          const err = await r.json().catch(() => ({}));
          if (err.message?.includes('unique') || err.code === '23505') {
            errorEl.textContent = 'Ya tienes una oferta activa para este viaje.';
          } else {
            errorEl.textContent = 'Error al enviar la oferta. Intenta de nuevo.';
          }
          errorEl.style.display = 'block';
          btn.disabled = false;
          btn.textContent = 'Enviar oferta →';
          return;
        }

        successEl.textContent = '¡Oferta enviada! Te notificaremos cuando sea revisada.';
        successEl.style.display = 'block';
        btn.textContent = 'Oferta enviada ✓';

        // Actualizar conteo
        ofertasCounts[rt] = (ofertasCounts[rt] || 0) + 1;
        const countEl = document.querySelector(`[data-ofertas-rt="${rt}"]`);
        if (countEl) {
          const c = ofertasCounts[rt];
          countEl.innerHTML = `<span class="oc-dot"></span> ${c} oferta${c > 1 ? 's' : ''} recibida${c > 1 ? 's' : ''}`;
        }

        setTimeout(cerrarOfertaModal, 2000);
      } catch (e) {
        errorEl.textContent = 'Error de conexión. Verifica tu internet.';
        errorEl.style.display = 'block';
        btn.disabled = false;
        btn.textContent = 'Enviar oferta →';
      }
    }

    function abrirForm(idx, accion) {
      if (!usuarioActual) { abrirAuthModal('registro'); return; }

      if (perfilActual) {
        if (perfilActual.estado !== 'aprobado') {
          showToast('⏳ Cuenta en revisión — el proceso tarda unos minutos. ¿No has sido aprobado? <a href="https://wa.me/573214401975" target="_blank" style="color:#00BFD8;font-weight:700">Contáctanos por WhatsApp</a>');
          return;
        }
        abrirOfertaModal(idx, accion);
        return;
      }

      fetchPerfil(usuarioActual.id, tokenActual)
        .then((data) => {
          perfilActual = data;
          actualizarNav(perfilActual);
          if (!data) { showToast('No encontramos tu cuenta. Cerrá sesión e ingresá de nuevo.'); return; }
          if (data.estado !== 'aprobado') { showToast('⏳ Tu cuenta está en revisión.'); return; }
          abrirOfertaModal(idx, accion);
        });
    }

    // ================================================================
    // DICCIONARIO DE CIUDADES
    // ================================================================
    // Coordenadas [latitud, longitud] organizadas por región.
    // Cuando una ciudad no está aquí, se consulta Google Geocoding API.
    // Para agregar: busca las coordenadas en Google Maps (clic derecho → ¿Qué hay aquí?)
    const CIUDADES = {
      // ── Bodegas principales Logxie / Avgust ──
      'funza':   [4.7132, -74.1966],
      'yumbo':   [3.5928, -76.4944],
      'espinal': [4.1544, -74.8864],

      // ── Ciudades principales ──
      'bogota':        [4.7110, -74.0721],
      'bogotá':        [4.7110, -74.0721],
      'cali':          [3.4516, -76.5319],
      'medellin':      [6.2442, -75.5812],
      'medellín':      [6.2442, -75.5812],
      'barranquilla':  [10.9685, -74.7813],
      'cartagena':     [10.3910, -75.4794],
      'cucuta':        [7.8939, -72.5078],
      'cúcuta':        [7.8939, -72.5078],
      'bucaramanga':   [7.1253, -73.1198],
      'santa marta':   [11.2408, -74.2110],
      'monteria':      [8.7575, -75.8906],
      'montería':      [8.7575, -75.8906],
      'valledupar':    [10.4631, -73.2532],
      'riohacha':      [11.5444, -72.9072],
      'sincelejo':     [9.3047, -75.3978],
      'neiva':         [2.9273, -75.2820],
      'ibague':        [4.4389, -75.2322],
      'ibagué':        [4.4389, -75.2322],
      'villavicencio': [4.1420, -73.6266],
      'aguachica':     [8.3081, -73.6189],

      // ── Eje Cafetero ──
      'manizales':          [5.0703, -75.5138],
      'pereira':            [4.8087, -75.6906],
      'armenia':            [4.5339, -75.6811],
      'cartago':            [4.7454, -75.9120],
      'la virginia':        [4.9000, -75.8833],
      'dosquebradas':       [4.8378, -75.6742],
      'santa rosa de cabal':[4.8680, -75.6256],
      'santa rosa':         [4.8680, -75.6256],
      'chinchina':          [4.9815, -75.6091],
      'chinchiná':          [4.9815, -75.6091],
      'calarca':            [4.5225, -75.6437],
      'calarcá':            [4.5225, -75.6437],
      'montenegro':         [4.5662, -75.7497],
      'quimbaya':           [4.6227, -75.7636],
      'belalcazar':         [4.9936, -75.8131],
      'belalcázar':         [4.9936, -75.8131],

      // ── Boyacá (zona frecuente de Avgust) ──
      'tunja':        [5.5353, -73.3678],
      'duitama':      [5.8281, -73.0297],
      'sogamoso':     [5.7150, -72.9267],
      'paipa':        [5.7833, -73.1167],
      'ramiriqui':    [5.4000, -73.3333],
      'ramiriquí':    [5.4000, -73.3333],
      'chiquinquira': [5.6167, -73.8167],
      'chiquinquirá': [5.6167, -73.8167],
      'buenavista':   [5.7167, -73.9667],
      'ventaquemada': [5.4167, -73.5167],
      'sachica':      [5.6667, -73.6833],
      'jenesano':              [5.3833, -73.4167],
      'jenessano':             [5.3833, -73.4167],
      'jenesano de boyaca':    [5.3833, -73.4167],
      'jenesano boyaca':       [5.3833, -73.4167],
      'tuta':         [5.6667, -73.2000],
      'toca':         [5.5667, -73.1667],
      'tibana':       [5.3167, -73.3833],
      'tibaná':       [5.3167, -73.3833],
      'arcabuco':     [5.7667, -73.4333],
      'macheta':      [5.0333, -73.8333],
      'umbita':       [5.3000, -73.5167],
      'aquitania':    [5.5167, -72.8833],
      'saboya':       [5.7000, -73.7667],
      'samaca':       [5.4833, -73.4833],
      'samacá':       [5.4833, -73.4833],
      'sutamarchan':  [5.6333, -73.7833],
      'miraflores':   [5.1981, -73.1456],

      // ── Cundinamarca ──
      'siberia':      [4.8856, -74.1483],
      'cabrera':      [3.9847, -74.4856],
      'fusagasuga':   [4.3367, -74.3644],
      'fusagasugá':   [4.3367, -74.3644],
      'silvania':     [4.4000, -74.4833],
      'sibate':       [4.4878, -74.2597],
      'sibaté':       [4.4878, -74.2597],
      'san bernardo': [4.1833, -74.4333],
      'usme':         [4.4367, -74.1322],
      'subachoque':   [4.9167, -74.2667],
      'fomeque':      [4.4833, -73.9000],
      'fómeque':      [4.4833, -73.9000],
      'ortigal':      [3.2798, -76.3449],
      'tenjo':        [4.8714, -74.1436],
      'zipaquira':    [5.0228, -74.0061],
      'zipaquirá':    [5.0228, -74.0061],
      'facatativa':   [4.8142, -74.3597],
      'facatativá':   [4.8142, -74.3597],
      'mosquera':     [4.7066, -74.2303],
      'madrid':       [4.7339, -74.2644],
      'soacha':       [4.5797, -74.2167],
      'chia':         [4.8614, -73.9314],
      'chía':         [4.8614, -73.9314],
      'cajica':       [4.9186, -74.0028],
      'cajicá':       [4.9186, -74.0028],
      'tocancipa':    [4.9678, -73.9139],
      'tocancipá':    [4.9678, -73.9139],
      'gachancipa':   [4.9969, -73.8717],

      // ── Santander ──
      'barrancabermeja': [7.0653, -73.8546],
      'giron':           [7.0725, -73.1686],
      'girón':           [7.0725, -73.1686],
      'floridablanca':   [7.0639, -73.0880],
      'piedecuesta':     [6.9868, -73.0522],
      'lebrija':         [7.1167, -73.2167],
      'san gil':         [6.5567, -73.1356],
      'socorro':         [6.5133, -73.2642],
      'velez':           [6.0125, -73.6778],
      'vélez':           [6.0125, -73.6778],
      'barbosa':         [5.9364, -73.6189],

      // ── Llanos Orientales ──
      'yopal':           [5.3378, -72.3952],
      'arauca':          [7.0897, -70.7617],
      'acacias':         [3.9894, -73.7597],
      'granada':         [3.5461, -73.7229],
      'aguazul':         [5.1739, -72.5506],
      'puerto lopez':    [4.0847, -72.9583],
      'restrepo':        [4.2572, -73.5703],
      'cumaral':         [4.2708, -73.4864],

      // ── Sur (Cauca, Nariño, Putumayo) ──
      'pasto':           [1.2136, -77.2811],
      'popayan':         [2.4448, -76.6147],
      'popayán':         [2.4448, -76.6147],
      'mocoa':           [1.1520, -76.6481],
      'florencia':       [1.6144, -75.6062],
      'el tigre':        [0.3500, -75.1833],
      'puerto asis':     [0.5000, -76.5000],
      'puerto asís':     [0.5000, -76.5000],
      'orito':           [0.6667, -76.8667],
      'la hormiga':      [0.0833, -76.9000],
      'sibundoy':        [1.2000, -76.9167],
      'villagarzon':     [1.0333, -76.6167],
      'villagarzón':     [1.0333, -76.6167],

      // ── Capitales departamentales adicionales ──
      'leticia':         [-4.2153, -69.9401],
      'mitu':            [1.2531, -70.2333],
      'puerto inirida':  [3.8653, -67.9239],
      'san jose del guaviare': [2.5694, -72.6416],
      'quibdo':          [5.6919, -76.6583],
      'quibdó':          [5.6919, -76.6583],
      'puerto carreno':  [6.1893, -67.4841],
    };

    // Caché de geocoding para no repetir llamadas a la API
    const geocodeCache = {};

    // ================================================================
    // FUNCIONES DE UTILIDAD
    // ================================================================

    /**
     * Busca coordenadas en el diccionario local.
     * Normaliza para manejar tildes y mayúsculas.
     */
    function normalizarNombre(str) {
      return str.toLowerCase()
        .normalize('NFD').replace(/[\u0300-\u036f]/g, '')  // sin tildes
        .replace(/[.\-_()]/g, ' ')                         // puntuación → espacio
        .replace(/\s+/g, ' ').trim();
    }

    // Genera variantes del nombre para buscar en el diccionario:
    // "Jenesano de Boyacá" → ["jenesano de boyaca", "jenesano", "de boyaca"]
    // "San Gil (Santander)" → ["san gil santander", "san gil", "santander"]
    function variantes(nombre) {
      const base = normalizarNombre(nombre);
      const partes = base.split(' ');
      const vs = [base];
      // Quitar sufijos tipo "de X", "del X" al final
      const stopwords = ['de','del','la','el','los','las','y'];
      for (let i = 1; i < partes.length; i++) {
        if (stopwords.includes(partes[i - 1]) || stopwords.includes(partes[i])) {
          vs.push(partes.slice(0, i).join(' '));
          vs.push(partes.slice(i + 1).join(' '));
        }
      }
      // Primera palabra sola (si tiene más de 4 letras para evitar falsos positivos)
      if (partes[0].length > 4) vs.push(partes[0]);
      return [...new Set(vs.filter(Boolean))];
    }

    function getCoordenadas(ciudad) {
      if (!ciudad) return null;
      const candidatos = variantes(ciudad);
      // Pass 1: exact match (evita que "santa" matchee "santa marta" por substring)
      for (const cand of candidatos) {
        for (const [nombre, coords] of Object.entries(CIUDADES)) {
          if (normalizarNombre(nombre) === cand) return coords;
        }
      }
      // Pass 2: substring match solo para candidatos específicos (>=5 chars)
      for (const cand of candidatos) {
        if (cand.length < 5) continue;
        for (const [nombre, coords] of Object.entries(CIUDADES)) {
          const n = normalizarNombre(nombre);
          if (n.includes(cand) || cand.includes(n)) return coords;
        }
      }
      return null;
    }

    /**
     * Consulta Google Geocoding API para ciudades no encontradas localmente.
     * Usa caché para no repetir la misma consulta dos veces.
     */
    async function geocodeCiudad(ciudad) {
      if (!ciudad) return null;
      const key = ciudad.toLowerCase().trim();

      // 1. Caché en memoria (misma sesión)
      if (geocodeCache[key]) return geocodeCache[key];

      // 2. Google Geocoding API
      try {
        const query = encodeURIComponent(ciudad + ', Colombia');
        const url = `https://maps.googleapis.com/maps/api/geocode/json?address=${query}&key=${GMAPS_KEY}`;
        const resp = await fetch(url);
        const data = await resp.json();
        if (data.results && data.results.length > 0) {
          const loc = data.results[0].geometry.location;
          const coords = [loc.lat, loc.lng];
          geocodeCache[key] = coords;
          return coords;
        }
      } catch (e) {
        console.warn('Geocoding falló para:', ciudad);
      }
      return null;
    }

    /**
     * Obtiene coordenadas: 1) diccionario local  2) Google API
     */
    async function getCoords(ciudad) {
      return getCoordenadas(ciudad) || await geocodeCiudad(ciudad);
    }

    /**
     * Formatea peso: 1219 → "1.2 ton", 800 → "800 kg"
     */
    function formatPeso(kg) {
      const n = parseFloat(kg);
      if (isNaN(n) || n === 0) return '—';
      return n >= 1000
        ? `${(n / 1000).toFixed(1)} ton`
        : `${Math.round(n)} kg`;
    }

    /**
     * Formatea número como moneda colombiana.
     * 1200000 → "$1.200.000"
     */
    function formatCOP(valor) {
      if (!valor || valor === 0) return 'A convenir';
      return new Intl.NumberFormat('es-CO', {
        style: 'currency',
        currency: 'COP',
        maximumFractionDigits: 0
      }).format(valor);
    }

    /**
     * Formatea precio compacto para el pin del mapa: 1200000 → "$1.2M", 800000 → "$800K"
     */
    function formatPrecioCorto(precio) {
      const n = parseFloat(precio);
      if (!n || n === 0) return null;
      if (n >= 1000000) {
        const m = n / 1000000;
        return '$' + (Number.isInteger(m) ? m : m.toFixed(1)) + 'M';
      }
      return '$' + Math.round(n / 1000) + 'K';
    }

    /**
     * Crea el divIcon de Leaflet con el pin de precio estilo Airbnb.
     * activo=true → fondo navy (seleccionado), activo=false → fondo blanco
     */
    function crearMarkerOrigen(coord, precioCorto, idx, origenLabel, destinosLabel) {
      const texto = precioCorto || 'A convenir';
      const w = texto.length > 7 ? 90 : 68;
      const icon = L.divIcon({
        html: `<div class="precio-pin">${texto}</div>`,
        iconSize: [w, 28],
        iconAnchor: [w / 2, 36],
        className: ''
      });
      const marker = L.marker(coord, { icon });
      if (origenLabel || destinosLabel) {
        const preview = `<div class="pin-preview"><b>${origenLabel}</b><div class="pin-preview-dest">→ ${destinosLabel}</div></div>`;
        marker.bindTooltip(preview, { direction: 'top', offset: [0, -38], className: 'pin-preview-tooltip' });
      }
      marker.on('click', (e) => {
        L.DomEvent.stopPropagation(e);
        seleccionarViaje(idx);
      });
      return marker;
    }

    function activarMarkerOrigen(marker, activo) {
      const el = marker.getElement()?.querySelector('.precio-pin');
      if (el) el.classList.toggle('activo', activo);
    }

    // ================================================================
    // PARSEAR CSV
    // ================================================================
    /**
     * Convierte el texto CSV de Google Sheets en un array de objetos.
     *
     * El CSV tiene esta estructura:
     * ORIGEN,DESTINO,FECHA_CARGUE,...
     * Funza,Cúcuta,31/03/2026,...
     *
     * Devuelve: [{ origen: 'Funza', destino: 'Cúcuta', ... }]
     *
     * El parser maneja campos vacíos (doble coma: ,,) y campos entre comillas.
     * Esto es importante porque el campo OTRO puede estar vacío.
     */
    function parseCSV(text) {
      const lineas = text.trim().split('\n');
      if (lineas.length < 2) return []; // Sin datos

      // Primera línea = headers (en minúsculas para facilitar el acceso)
      const headers = lineas[0]
        .split(',')
        .map(h => h.trim().replace(/"/g, '').toLowerCase());

      // Resto de líneas = datos
      return lineas.slice(1).map(linea => {
        // Parser carácter por carácter para manejar comas dentro de comillas
        const valores = [];
        let valorActual = '';
        let dentroDeComillas = false;

        for (let i = 0; i < linea.length; i++) {
          const caracter = linea[i];
          if (caracter === '"') {
            dentroDeComillas = !dentroDeComillas;
          } else if (caracter === ',' && !dentroDeComillas) {
            valores.push(valorActual.trim());
            valorActual = '';
          } else {
            valorActual += caracter;
          }
        }
        valores.push(valorActual.trim()); // Último valor

        // Crear objeto mapeando header[i] → valor[i]
        const objeto = {};
        headers.forEach((header, i) => {
          objeto[header] = (valores[i] || '').replace(/"/g, '').trim();
        });
        return objeto;
      });
    }

    // ================================================================
    // RENDERIZAR TARJETAS DE VIAJE
    // ================================================================
    /**
     * Recibe el array de viajes (desde el CSV) y genera las tarjetas HTML.
     *
     * Lógica importante:
     * - Agrupa por RT_TOTAL para que un viaje con múltiples RMs
     *   aparezca como UNA sola tarjeta (no duplicados)
     * - Si hay precio_base → muestra "Aceptar →" y "Hacer oferta"
     * - Si no hay precio → muestra "A convenir" con botón "Ofertar →"
     * - Los primeros 2 viajes se marcan como "🔥 Nuevo"
     */
    function actualizarTicker(viajes) {
      const track = document.getElementById('ticker-track');
      const bar   = document.getElementById('ticker-bar');
      if (!viajes || viajes.length === 0) return;

      const items = viajes.map(v => {
        const origen   = (v.origen  || '').split(',')[0].trim();
        const destinos = (v.destino || '').split(',').map(d => d.trim()).filter(Boolean);
        const dest     = destinos.length > 1 ? `${destinos[0]} +${destinos.length - 1} destinos` : destinos[0] || '—';
        const precio   = estimarPrecio(v.km, v.peso_kg, (v.destino||'').split(',').length, v.destino, v.origen);
        const precioTxt = precio > 0 ? formatPrecioCorto(precio) : 'A convenir';

        const hoy   = new Date(); hoy.setHours(0,0,0,0);
        const partes = (v.fecha_cargue || '').split('/');
        const fecha = partes.length === 3 ? new Date(+partes[2], +partes[1]-1, +partes[0]) : null;
        const dias  = fecha ? Math.ceil((fecha - hoy) / 86400000) : 99;
        const badge = dias <= 0 ? '⚡' : dias <= 2 ? '🔥' : '📦';

        return `<span class="ticker-item">${badge} ${origen} <span class="ti-sep">→</span> ${dest} <span class="ti-sep">·</span> <span class="ti-precio">${precioTxt}</span></span>`;
      }).join('<span class="ticker-item" style="color:rgba(255,255,255,0.2)">|</span>');

      // Duplicar para loop infinito
      track.innerHTML = items + items;
      bar.style.display = 'flex';

      // Velocidad basada en píxeles/segundo — se adapta a cualquier pantalla
      track.style.animationDuration = '9999s'; // temporal para medir
      requestAnimationFrame(() => {
        const contentWidth = track.scrollWidth / 2; // mitad porque está duplicado
        const pxPerSec = 110; // velocidad cómoda de lectura
        const duracion = Math.max(8, contentWidth / pxPerSec);
        track.style.animationDuration = duracion + 's';
      });
    }

    // Parsear fecha DD/MM/YYYY → Date
    function parseFecha(str) {
      if (!str) return null;
      const p = str.split('/');
      if (p.length !== 3) return null;
      return new Date(parseInt(p[2]), parseInt(p[1]) - 1, parseInt(p[0]));
    }

    function renderViajes(viajes, gridId = 'viajes-grid', esRetorno = false) {
      const grid     = document.getElementById(gridId);
      const subtitle = gridId === 'viajes-grid' ? document.getElementById('viajes-subtitle') : null;

      if (!viajes.length) {
        grid.innerHTML = '<div class="loading-msg">No hay viajes disponibles en este momento. Vuelve pronto.</div>';
        subtitle.textContent = 'Actualizado en tiempo real desde nuestra red';
        return;
      }

      if (subtitle) subtitle.textContent = `${viajes.length} viaje${viajes.length !== 1 ? 's' : ''} disponible${viajes.length !== 1 ? 's' : ''} ahora mismo`;

      // ── Generar HTML de cada tarjeta ─────────────────────────
      grid.innerHTML = viajes.map((v, idx) => {
        // idxReal apunta al índice en viajesData completo para que seleccionarViaje() use el mapa correcto
        const idxReal = viajesData.indexOf(v);
        const retornoTag = esRetorno ? '<div class="viaje-retorno-tag">↩ retorno disponible</div>' : '';

        // Datos básicos del viaje
        const origen    = v.origen     || '';
        const destino   = v.destino    || '';
        const peso      = v.peso_kg    || '0';
        const fecha     = v.fecha_cargue || '';
        const tipo      = (v.tipo_mercancia || '').trim() || 'General';
        const precioBase = estimarPrecio(v.km, v.peso_kg, (v.destino||'').split(',').length, v.destino, v.origen);
        const kmReales  = v.km      || '';
        const minutos   = v.minutos || '';
        // Badge dinámico basado en fecha de cargue

        // Conteo de unidades por tipo
        const contenedores = parseInt(v.contenedores       || '0');
        const cajas        = parseInt(v.cajas              || '0');
        const bidones      = parseInt(v.bidones            || '0');
        const canecas      = parseInt(v.canecas            || '0');
        const uSueltas     = parseInt(v.unidades_sueltas   || '0');

        // Construir texto de unidades (solo los que tienen valor)
        const unidades = [];
        if (contenedores > 0) unidades.push(`${contenedores} contenedores`);
        if (cajas        > 0) unidades.push(`${cajas} cajas`);
        if (bidones      > 0) unidades.push(`${bidones} bidones`);
        if (canecas      > 0) unidades.push(`${canecas} canecas`);
        if (uSueltas     > 0) unidades.push(`${uSueltas} uds sueltas`);
        const unidadesTexto = unidades.join(', ') || 'Ver detalle';

        // Procesar destinos múltiples
        const destinos      = destino.split(',').map(d => d.trim()).filter(Boolean);
        const destinoResumen = destinos.length > 1
          ? `${destinos[0]} +${destinos.length - 1} destinos`
          : destino;
        const destinoDetalle = destinos.length > 1
          ? destinos.join(' · ')
          : '';

        // Lógica de countdown: fecha pasada = cargue inmediato, futura = cuenta regresiva
        const ahora = new Date();
        ahora.setHours(0,0,0,0);
        let fechaCargue = null;
        let esInmediato = false;
        let countdownHTML = '';
        if (fecha) {
          const partes = fecha.split('/');
          if (partes.length === 3) {
            fechaCargue = new Date(partes[2], partes[1] - 1, partes[0]);
            fechaCargue.setHours(0,0,0,0);
          }
        }
        let diffDias = null;
        if (fechaCargue && fechaCargue <= ahora) {
          esInmediato = true;
          countdownHTML = `<div class="viaje-countdown cd-urgente"><span class="cd-icon">⚡</span><span class="cd-text">Cargue inmediato — se necesita vehículo ya</span></div>`;
        } else if (fechaCargue) {
          diffDias = Math.ceil((fechaCargue - ahora) / 86400000);
          if (diffDias <= 2) {
            countdownHTML = `<div class="viaje-countdown cd-urgente"><span class="cd-icon">⏰</span><span class="cd-text">Cierra en ${diffDias === 1 ? '1 día' : diffDias + ' días'}</span></div>`;
          } else if (diffDias <= 5) {
            countdownHTML = `<div class="viaje-countdown"><span class="cd-icon">⏳</span><span class="cd-text">Subasta abierta · carga en ${diffDias} días</span></div>`;
          } else {
            countdownHTML = `<div class="viaje-countdown"><span class="cd-icon">📅</span><span class="cd-text">Carga en ${diffDias} días</span></div>`;
          }
        }

        let badgeClass, badgeText;
        if (esInmediato) {
          badgeClass = 'badge-urgente'; badgeText = '⚡ Urgente';
        } else if (diffDias !== null && diffDias <= 2) {
          badgeClass = 'badge-pronto'; badgeText = '🔥 Cierra pronto';
        } else if (diffDias !== null && diffDias <= 5) {
          badgeClass = 'badge-subasta'; badgeText = '⏳ Subasta abierta';
        } else {
          badgeClass = 'badge-disponible'; badgeText = '✓ Disponible';
        }

        // HTML de la tarjeta
        return `
          <div class="viaje-card" onclick="seleccionarViaje(${idxReal})" data-origen="${origen.split(',')[0].trim()}" data-destino="${destinos[0] || destino.split(',')[0].trim()}" data-precio="${precioBase > 0 ? formatCOP(precioBase) : ''}">
            ${retornoTag}
            <!-- Ruta + badge de estado -->
            <div class="viaje-header">
              <div>
                <div class="viaje-ruta">${origen} → ${destinoResumen}</div>
                ${destinoDetalle ? `<div style="font-size:11px;color:#9aa0b8;margin-top:2px;">${destinoDetalle}</div>` : ''}
                ${countdownHTML}
              </div>
              <span class="viaje-badge ${badgeClass}">
                ${badgeText}
              </span>
            </div>

            <!-- Metadatos del viaje (2x2 grid) -->
            <div class="viaje-meta">
              <div class="meta-item"><div class="meta-label">Peso total</div><div class="meta-value">${formatPeso(peso)}</div></div>
              <div class="meta-item"><div class="meta-label">Fecha cargue</div><div class="meta-value">${esInmediato ? 'Hoy' : (fecha || 'Por confirmar')}</div></div>
              <div class="meta-item"><div class="meta-label">Tipo</div><div class="meta-value">${tipo}</div></div>
              <div class="meta-item"><div class="meta-label">Unidades</div><div class="meta-value">${unidadesTexto}</div></div>
            </div>

            <!-- Precio y botones de acción -->
            ${precioBase > 0 ? `
              <!-- CON PRECIO: muestra precio base calculado por n8n + Distance Matrix API -->
              <div class="precio-base-box">
                <div class="precio-base-label">
                  Precio base
                  ${kmReales ? ` · ${kmReales} km` : ''}
                  ${minutos  ? ` · ${minutos}`     : ''}
                </div>
                <div class="precio-base-value">${formatCOP(precioBase)}</div>
                <div class="precio-base-sub">Acepta este precio o haz una oferta</div>
                <div class="ofertas-count" data-ofertas-rt="${v.rt_total || ''}"></div>
              </div>
              <div style="display:flex; gap:8px;">
                <button class="btn-aceptar" onclick="event.stopPropagation(); abrirForm(${idxReal}, 'aceptar')">Aceptar →</button>
                <button class="btn-menor"   onclick="event.stopPropagation(); abrirForm(${idxReal}, 'oferta')">Hacer oferta</button>
              </div>
            ` : `
              <!-- SIN PRECIO: viajes anteriores al sistema de cálculo automático -->
              <div class="viaje-footer">
                <div>
                  <div class="precio-label">Precio subasta</div>
                  <div class="precio-value">A convenir</div>
                </div>
                <button class="btn-ofertar" onclick="event.stopPropagation(); abrirForm(${idxReal}, 'oferta')">Ofertar →</button>
              </div>
              <div class="ofertas-count" data-ofertas-rt="${v.rt_total || ''}"></div>
            `}

          </div>
        `;
      }).join('');
    }

    // ================================================================
    // MAPA CON RUTAS ACTIVAS
    // ================================================================
    /**
     * Inicializa el mapa de Leaflet y dibuja las rutas de todos los viajes.
     *
     * Para cada viaje:
     * 1. Obtiene coordenadas del origen (cyan)
     * 2. Obtiene coordenadas de cada destino (navy con número)
     * 3. Traza una línea punteada entre todos los puntos
     * 4. Agrega popups con información al hacer clic
     *
     * Al final: fitBounds() hace zoom para ver todas las rutas.
     */
    let mapaLeaflet;        // instancia del mapa Leaflet
    let viajesData = [];    // array de viajes deduplicados (compartido entre tarjetas y mapa)

    /**
     * Obtiene la ruta real por carretera usando OSRM (gratis, sin API key).
     * Recibe array de puntos [[lat,lng], ...] y devuelve array de coordenadas de la ruta.
     * Si falla, devuelve null (fallback a línea recta).
     */
    async function obtenerRutaOSRM(puntos) {
      if (puntos.length < 2) return null;
      try {
        const coords = puntos.map(p => `${p[1]},${p[0]}`).join(';');
        const url = `https://router.project-osrm.org/route/v1/driving/${coords}?overview=full&geometries=geojson`;
        const resp = await fetch(url, { signal: AbortSignal.timeout(5000) });
        const data = await resp.json();
        if (data.code === 'Ok' && data.routes.length > 0) {
          return data.routes[0].geometry.coordinates.map(c => [c[1], c[0]]);
        }
      } catch (e) { /* silencioso — fallback a línea recta */ }
      return null;
    }
    let mapaCapas = [];     // [{grupo, bounds, originMarker, precioCorto, origen}] por índice
    let viajeSeleccionado = -1; // índice del viaje activo (-1 = todos visibles)

    async function initMapa(viajes) {
      if (!document.getElementById('map')) return;
      console.log(`[MAPA] initMapa llamado con ${viajes.length} viajes:`, viajes.map(v => v.origen + ' → ' + v.destino));
      mapaLeaflet = L.map('map', { zoomControl: true })
        .setView([4.5709, -74.2973], 6);

      L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
        attribution: '© OpenStreetMap © CARTO',
        subdomains: 'abcd',
        maxZoom: 18
      }).addTo(mapaLeaflet);

      mapaCapas = [];
      const todosLosPuntos = [];
      const origenesConteo = {}; // origen → cuántos viajes ya tienen pin ahí

      for (let viajeIdx = 0; viajeIdx < viajes.length; viajeIdx++) {
        const v = viajes[viajeIdx];
        const origen      = (v.origen || '').split(',')[0].trim();
        const destinos    = (v.destino || '').split(',').map(d => d.trim()).filter(Boolean);
        const precioBase  = estimarPrecio(v.km, v.peso_kg, (v.destino||'').split(',').length, v.destino, v.origen);
        const precioCorto = formatPrecioCorto(precioBase);

        const grupo      = L.layerGroup();
        const bounds     = [];
        const puntosRuta = [];
        let originMarker = null;

        // ── Pin de ORIGEN — desplazado si hay varios del mismo origen ──
        const coordBase = await getCoords(origen);
        if (!coordBase) console.warn(`[MAPA] Sin coords para ORIGEN: "${origen}" (viaje ${viajeIdx})`);
        let coordOrigen = null;
        if (coordBase) {
          const n = origenesConteo[origen] || 0;
          origenesConteo[origen] = n + 1;
          // Pequeño offset para que no se superpongan (0.012° ≈ 1.3 km)
          coordOrigen = n === 0 ? coordBase : [coordBase[0] + n * 0.06, coordBase[1] + n * 0.04];

          todosLosPuntos.push(coordOrigen);
          bounds.push(coordOrigen);
          puntosRuta.push(coordOrigen);

          originMarker = crearMarkerOrigen(coordOrigen, precioCorto, viajeIdx, v.origen, destinos.join(', '));
          grupo.addLayer(originMarker);
        }

        // ── Pins de DESTINOS (puntos navy con número) ──────────
        const destinosConCoord = await Promise.all(
          destinos.map(async d => ({ nombre: d, coord: await getCoords(d) }))
        );

        const destinosValidos = destinosConCoord.filter(d => d.coord !== null);

        // ── Detectar ruta circular: destino que vuelve al origen ──
        // Doble chequeo: por nombre Y por proximidad de coordenadas (< 0.05° ≈ 5km)
        const origenKey = normalizarNombre(origen);
        let destinoRetorno = null;
        let destinosParaOptimizar = [...destinosValidos];

        if (coordBase) {
          const idxRet = destinosValidos.findIndex(d => {
            const porNombre = variantes(d.nombre).some(v =>
              v === origenKey || origenKey.includes(v) || v.includes(origenKey)
            );
            const porCoord = d.coord &&
              Math.hypot(d.coord[0] - coordBase[0], d.coord[1] - coordBase[1]) < 0.05;
            return porNombre || porCoord;
          });
          if (idxRet !== -1) {
            destinoRetorno = destinosValidos[idxRet];
            destinosParaOptimizar = destinosValidos.filter((_, i) => i !== idxRet);
          }
        }

        // Paso 1: nearest-neighbor (sin el destino de retorno)
        const destinosOrdenados = [];
        let puntoActual = coordOrigen || (destinosParaOptimizar[0]?.coord ?? null);
        const pendientes = [...destinosParaOptimizar];
        while (pendientes.length > 0) {
          let minDist = Infinity, minIdx = 0;
          pendientes.forEach((d, i) => {
            const dist = Math.hypot(d.coord[0] - puntoActual[0], d.coord[1] - puntoActual[1]);
            if (dist < minDist) { minDist = dist; minIdx = i; }
          });
          destinosOrdenados.push(pendientes[minIdx]);
          puntoActual = pendientes[minIdx].coord;
          pendientes.splice(minIdx, 1);
        }

        // Paso 2: 2-opt
        if (destinosOrdenados.length > 3) {
          const pts = coordOrigen ? [{ coord: coordOrigen }, ...destinosOrdenados] : destinosOrdenados;
          const dist2 = (a, b) => Math.hypot(a.coord[0] - b.coord[0], a.coord[1] - b.coord[1]);
          const offset = coordOrigen ? 1 : 0;
          let improved = true;
          while (improved) {
            improved = false;
            for (let i = offset; i < pts.length - 1; i++) {
              for (let j = i + 1; j < pts.length; j++) {
                const before = dist2(pts[i - 1] ?? pts[0], pts[i]) + dist2(pts[j], pts[j + 1] ?? pts[pts.length - 1]);
                const after  = dist2(pts[i - 1] ?? pts[0], pts[j]) + dist2(pts[i], pts[j + 1] ?? pts[pts.length - 1]);
                if (after < before - 1e-10) {
                  pts.splice(i, j - i + 1, ...pts.slice(i, j + 1).reverse());
                  improved = true;
                }
              }
            }
          }
          destinosOrdenados.splice(0, destinosOrdenados.length, ...pts.slice(offset));
        }

        // Agregar retorno al final (forzado, fuera de la optimización)
        if (destinoRetorno) destinosOrdenados.push(destinoRetorno);

        const totalParadas = destinosOrdenados.length;
        destinosOrdenados.forEach((dest, i) => {
          todosLosPuntos.push(dest.coord);
          bounds.push(dest.coord);
          puntosRuta.push(dest.coord);

          const numParada = totalParadas > 1 ? `${i + 1}` : '';
          const esRetornoPin = destinoRetorno && i === totalParadas - 1;

          // Pin de retorno: cyan con ↩, pin normal: navy numerado
          const iconDest = L.divIcon({
            html: esRetornoPin
              ? `<div style="position:relative">
                   <div style="width:14px;height:14px;border-radius:50%;background:#00B4D8;border:2px solid white;box-shadow:0 2px 6px rgba(0,0,0,0.35)"></div>
                   <div style="position:absolute;top:-10px;left:12px;background:#00B4D8;color:white;font-size:9px;font-weight:700;padding:1px 5px;border-radius:4px;white-space:nowrap">↩ ${numParada}</div>
                 </div>`
              : `<div style="position:relative">
                   <div style="width:12px;height:12px;border-radius:50%;background:#1B2A6B;border:2px solid white;box-shadow:0 2px 6px rgba(0,0,0,0.3)"></div>
                   ${numParada ? `<div style="position:absolute;top:-8px;left:10px;background:#1B2A6B;color:white;font-size:9px;font-weight:700;padding:1px 4px;border-radius:4px;">${numParada}</div>` : ''}
                 </div>`,
            iconSize: [12, 12], iconAnchor: [6, 6], className: ''
          });

          grupo.addLayer(
            L.marker(dest.coord, { icon: iconDest })
              .bindPopup(esRetornoPin
                ? `<b style="color:#00B4D8">↩ Retorno · Parada ${numParada}:</b> ${dest.nombre}`
                : `<b style="color:#1B2A6B">Parada${numParada ? ' ' + numParada : ''}:</b> ${dest.nombre}`)
          );
        });

        // ── Si es circular, cerrar el loop agregando el origen al final de la ruta ──
        if (destinoRetorno && coordOrigen) {
          puntosRuta.push(coordOrigen);
        }

        // ── Ruta real por carretera (OSRM) con fallback a línea recta ──
        if (puntosRuta.length > 1) {
          // Línea recta punteada inmediata (se ve mientras carga OSRM)
          const lineaRecta = L.polyline(puntosRuta, {
            color: '#1B2A6B', weight: 2.5, opacity: 0.6, dashArray: '6 4'
          });
          grupo.addLayer(lineaRecta);

          // Intentar obtener ruta real (async, no bloquea)
          obtenerRutaOSRM(puntosRuta).then(rutaReal => {
            if (rutaReal) {
              grupo.removeLayer(lineaRecta);
              grupo.addLayer(L.polyline(rutaReal, {
                color: '#1B2A6B', weight: 3, opacity: 0.75
              }));
            }
            // Si falla, la línea recta ya está visible
          });
        }

        grupo.addTo(mapaLeaflet);
        mapaCapas.push({ grupo, bounds, originMarker, precioCorto, origen });
      }

      // ── Zoom para ver todas las rutas ─────────────────────────
      if (todosLosPuntos.length > 1) {
        mapaLeaflet.fitBounds(todosLosPuntos, { padding: [40, 40], maxZoom: 12 });
      }

      // ── Leyenda ───────────────────────────────────────────────
      const leyenda = L.control({ position: 'bottomleft' });
      leyenda.onAdd = () => {
        const div = L.DomUtil.create('div');
        div.innerHTML = `
          <div style="background:white;padding:8px 12px;border-radius:8px;border:1px solid #eef0f6;font-family:'DM Sans',sans-serif;font-size:11px;">
            <div style="display:flex;align-items:center;gap:6px;margin-bottom:6px;">
              <div style="background:white;border:2px solid #1B2A6B;border-radius:8px;padding:1px 6px;font-size:9px;font-weight:700;color:#1B2A6B;">$</div>
              <span style="color:#5a6280">Origen · precio</span>
            </div>
            <div style="display:flex;align-items:center;gap:6px;">
              <div style="width:10px;height:10px;border-radius:50%;background:#1B2A6B;"></div>
              <span style="color:#5a6280">Destino</span>
            </div>
          </div>`;
        return div;
      };
      leyenda.addTo(mapaLeaflet);
    }

    // ================================================================
    // CARGAR DATOS DESDE GOOGLE SHEETS
    // ================================================================
    /**
     * Función principal que orquesta todo:
     * 1. Descarga el CSV de Google Sheets
     * 2. Lo parsea en objetos JavaScript
     * 3. Renderiza las tarjetas
     * 4. Inicializa el mapa
     *
     * Si algo falla, muestra datos de ejemplo para que la página
     * no quede en blanco durante desarrollo o si Sheets no responde.
     */
    async function cargarViajes() {
      try {
        const respuesta = await fetch(CSV_URL);
        if (!respuesta.ok) throw new Error('No se pudo cargar el CSV');

        const texto  = await respuesta.text();
        const viajes = parseCSV(texto);

        // Generar ID único por viaje y deduplicar
        const rtVistos = {};
        viajesData = [];
        viajes.forEach((v, i) => {
          // Si no hay rt_total, generar ID desde origen+destino+fecha+peso
          if (!v.rt_total) {
            const raw = `${v.origen}|${v.destino}|${v.fecha_cargue}|${v.peso_kg}`.toLowerCase();
            let hash = 0;
            for (let c = 0; c < raw.length; c++) hash = ((hash << 5) - hash + raw.charCodeAt(c)) | 0;
            v.rt_total = 'v-' + Math.abs(hash).toString(36);
          }
          const rt = v.rt_total;
          if (!rtVistos[rt]) { rtVistos[rt] = true; viajesData.push(v); }
        });

        renderViajes(viajesData);
        actualizarTicker(viajesData);
        await initMapa(viajesData);
        cargarConteosOfertas();
        if (typeof _heroDrawFn === 'function') _heroDrawFn(viajesData);

      } catch (error) {
        console.warn('Error al cargar viajes:', error);

        viajesData = [
          { origen: 'Funza', destino: 'Cucuta, Bucaramanga, Aguachica', peso_kg: '1219', fecha_cargue: '31/03/2026', tipo_mercancia: 'Productos químicos', cajas: '40', precio_base: '1200000', km: '600', minutos: '10h 30min', rt_total: 'demo-1' },
          { origen: 'Yumbo', destino: 'El Tigre, Pasto',                peso_kg: '2802', fecha_cargue: '06/04/2026', tipo_mercancia: 'Productos químicos', cajas: '150', precio_base: '0', rt_total: 'demo-2' },
        ];

        renderViajes(viajesData);
        await initMapa(viajesData);
        if (typeof _heroDrawFn === 'function') _heroDrawFn(viajesData);
      }
    }

    // ================================================================
    // FUNCIONES DE UI (Interfaz de Usuario)
    // ================================================================

    /**
     * Selecciona/deselecciona una tarjeta de viaje.
     * Al seleccionar: resalta la tarjeta, oculta el resto en el mapa,
     * activa el pin de precio y hace zoom a esa ruta.
     * Al volver a hacer clic: restaura todo.
     */
    function seleccionarViaje(idx) {
      const cards = document.querySelectorAll('.viaje-card');

      if (viajeSeleccionado === idx) {
        // Deseleccionar → mostrar todo
        viajeSeleccionado = -1;
        cards.forEach(c => c.classList.remove('selected'));
        document.getElementById('btn-ver-todos').classList.remove('visible');
        mapaCapas.forEach((capa) => {
          if (!mapaLeaflet.hasLayer(capa.grupo)) capa.grupo.addTo(mapaLeaflet);
          if (capa.originMarker) activarMarkerOrigen(capa.originMarker, false);
        });
        const todos = mapaCapas.flatMap(c => c.bounds);
        if (todos.length > 1) mapaLeaflet.fitBounds(todos, { padding: [40, 40], maxZoom: 12, animate: false });
        return;
      }

      // Seleccionar
      viajeSeleccionado = idx;
      cards.forEach((c, i) => c.classList.toggle('selected', i === idx));
      document.getElementById('btn-ver-todos').classList.add('visible');

      mapaCapas.forEach((capa, i) => {
        if (i === idx) {
          if (!mapaLeaflet.hasLayer(capa.grupo)) capa.grupo.addTo(mapaLeaflet);
          if (capa.originMarker) activarMarkerOrigen(capa.originMarker, true);
        } else {
          mapaLeaflet.removeLayer(capa.grupo);
        }
      });

      if (mapaCapas[idx] && mapaCapas[idx].bounds.length > 1) {
        mapaLeaflet.fitBounds(mapaCapas[idx].bounds, { padding: [60, 60], maxZoom: 12, animate: false });
      } else if (mapaCapas[idx] && mapaCapas[idx].bounds.length === 1) {
        mapaLeaflet.setView(mapaCapas[idx].bounds[0], 9, { animate: false });
      }

      // Calculadora movida a transportador.html — no actualizar sliders aquí

      // Scroll suave al mapa
      document.getElementById('map').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }

    /**
     * Cambia entre los tabs "Para empresas" y "Para transportadores"
     * en la sección "¿Cómo funciona?".
     * @param {string} tab - 'empresa' o 'conductor'
     * @param {HTMLElement} btn - El botón que se hizo clic
     */
    function cambiarTab(tab, btn) {
      // Desactivar todos los tabs y secciones
      document.querySelectorAll('.como-tab').forEach(t => t.classList.remove('active'));
      document.querySelectorAll('.como-steps').forEach(s => s.classList.remove('active'));
      // Activar el tab y sección seleccionados
      btn.classList.add('active');
      document.getElementById(`steps-${tab}`).classList.add('active');
    }

    function togglePass(inputId, icon) {
      const input = document.getElementById(inputId);
      const visible = input.type === 'text';
      input.type = visible ? 'password' : 'text';
      icon.style.opacity = visible ? '0.5' : '1';
    }

    /**
     * Muestra un mensaje temporal en la esquina inferior derecha.
     * Se usa para botones que aún no tienen funcionalidad real.
     * @param {string} mensaje - Texto a mostrar
     */
    function showToast(mensaje) {
      const toast = document.getElementById('toast');
      toast.innerHTML = mensaje;
      toast.classList.add('show');
      setTimeout(() => toast.classList.remove('show'), 5000);
    }

    /**
     * Copia el código de cupón al portapapeles y muestra confirmación visual.
     * @param {HTMLElement} el - El elemento del código cupón
     */
    function copiarCodigo(el) {
      navigator.clipboard.writeText('LOGXIE20').then(() => {
        const textoOriginal = el.textContent;
        el.textContent = '¡Copiado!';
        setTimeout(() => el.textContent = textoOriginal, 2000);
      });
    }

    // ================================================================
    // POLLING — revisar viajes nuevos cada 3 minutos
    // ================================================================
    let viajesPendientes = null; // viajes nuevos detectados pero no mostrados

    async function revisarNuevosViajes() {
      try {
        const resp = await fetch(CSV_URL);
        if (!resp.ok) return;
        const texto = await resp.text();
        const viajes = parseCSV(texto);
        const rtVistos = {};
        const nuevos = [];
        viajes.forEach((v, i) => {
          if (!v.rt_total) {
            const raw = `${v.origen}|${v.destino}|${v.fecha_cargue}|${v.peso_kg}`.toLowerCase();
            let hash = 0;
            for (let c = 0; c < raw.length; c++) hash = ((hash << 5) - hash + raw.charCodeAt(c)) | 0;
            v.rt_total = 'v-' + Math.abs(hash).toString(36);
          }
          const rt = v.rt_total;
          if (!rtVistos[rt]) { rtVistos[rt] = true; nuevos.push(v); }
        });
        if (nuevos.length !== viajesData.length) {
          viajesPendientes = nuevos;
          const diff = nuevos.length - viajesData.length;
          const banner = document.getElementById('nuevos-banner');
          const texto2 = diff > 0
            ? `${diff} viaje${diff > 1 ? 's' : ''} nuevo${diff > 1 ? 's' : ''} disponible${diff > 1 ? 's' : ''}`
            : 'Los viajes se han actualizado';
          document.getElementById('nuevos-banner-text').textContent = texto2;
          banner.classList.add('visible');
        }
      } catch (e) { /* silencioso */ }
    }

    async function aplicarNuevosViajes() {
      const banner = document.getElementById('nuevos-banner');
      banner.classList.remove('visible');
      if (viajesPendientes) {
        viajesData = viajesPendientes;
        viajesPendientes = null;
        viajeSeleccionado = -1;
        renderViajes(viajesData);
        // Limpiar mapa y reinicializar
        if (mapaLeaflet) { mapaLeaflet.remove(); mapaLeaflet = null; }
        await initMapa(viajesData);
      }
    }

    // ================================================================
    // INICIO
    // ================================================================
    cargarViajes();
    setInterval(revisarNuevosViajes, 180000);
    // Aplicar rol guardado después de que el DOM y los viajes carguen
    if (rolActivo) setTimeout(aplicarRol, 800);


    // CALCULADORA DE FLETE — modelo polinomial grado 2 + paradas + zona (Ridge, n=1.015 viajes reales)
    // Misma fórmula que n8n v2 para que los precios coincidan
    const CC_RANGOS = [
      { label:'< 100 km',    min:0,    max:100,  p25:380000,   p75:800000   },
      { label:'100–300 km',  min:100,  max:300,  p25:900000,   p75:1695000  },
      { label:'300–600 km',  min:300,  max:600,  p25:1500000,  p75:2602500  },
      { label:'600–1000 km', min:600,  max:1000, p25:1040025,  p75:4506945  },
      { label:'≥ 1000 km',   min:1000, max:9999, p25:4250000,  p75:11030000 },
    ];
    const CC_ZONA_AJUSTE = {
      'HUB':0,'ANTIOQUIA':15759,'BOYACA':87756,'CENTRO':22045,'CUNDINAMARCA':65602,
      'EJE CAFETERO':-18794,'LLANOS':159210,'NORTE':79189,'OCCIDENTE':10720,
      'ORIENTE':-176447,'SANTANDERES':-213483,'SUR':79189,'TOLHUIL':-18146,'VALLE':34226
    };

    // Listas de ciudades por zona — idénticas a n8n v2 para detección automática
    const CC_ZONAS_CIUDADES = {
      'LLANOS':       ['villavicencio','yopal','arauca','acacias','granada','puerto lopez','restrepo','cumaral','aguazul','tauramena','trinidad','paz de ariporo','orocue','san martin'],
      'BOYACA':       ['tunja','duitama','sogamoso','chiquinquira','paipa','villa de leyva','samaca','ventaquemada','tibasosa','nobsa'],
      'SANTANDERES':  ['bucaramanga','cucuta','giron','floridablanca','piedecuesta','san gil','barrancabermeja','pamplona','ocana','los patios'],
      'ORIENTE':      ['bucaramanga','cucuta','giron','floridablanca','piedecuesta','pamplona'],
      'CUNDINAMARCA': ['zipaquira','chia','facatativa','soacha','mosquera','madrid','cajica','cota','tenjo','tabio','la calera','fusagasuga','silvania','tocancipa'],
      'EJE CAFETERO': ['virginia','cartago','armenia','manizales','santa rosa','chinchina','pereira','dosquebradas','la virginia','calarca','montenegro','quimbaya','belalcazar'],
      'VALLE':        ['cali','palmira','buga','tulua','yumbo','jamundi','candelaria','ginebra','la union'],
      'ANTIOQUIA':    ['medellin','rionegro','envigado','itagui','bello','sabaneta','la ceja','marinilla','guarne','caucasia','apartado','turbo'],
      'CENTRO':       ['ibague','girardot','melgar','honda','mariquita','flandes','guamo'],
      'TOLHUIL':      ['neiva','garzon','pitalito','campoalegre','la plata','san agustin','espinal','natagaima','purificacion'],
      'OCCIDENTE':    ['cali','palmira','buga','tulua','sevilla','buenaventura','jamundi','candelaria','ginebra','el cerrito','dagua'],
      'NORTE':        ['monteria','valledupar','barranquilla','cartagena','santa marta','sincelejo','riohacha','lorica','cerete','magangue','mompox','el banco','aguachica'],
      'SUR':          ['pasto','ipiales','tumaco','popayan','mocoa','el tigre','puerto asis','orito','la hormiga','sibundoy','villagarzon','santander de quilichao','miranda','patia','florencia','belen de los andaquies'],
    };

    function ccNorm(s) { return (s||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,''); }
    function ccFmt(n) { return '$' + Math.round(n).toLocaleString('es-CO'); }
    function ccRango(km) { return CC_RANGOS.find(r => km >= r.min && km < r.max) || CC_RANGOS[CC_RANGOS.length-1]; }

    // Bodegas hub — misma lista que n8n v2
    const CC_HUB = ['funza','yumbo','espinal'];
    const CC_PRECIO_MINIMO = 950000;

    // Calcula el precio estimado usando la misma fórmula del slider
    // Usado en tarjetas, mapa y ticker para consistencia con la calculadora
    function estimarPrecio(km, kg, paradas, destino, origen) {
      km      = parseInt(km)      || 0;
      kg      = parseInt(kg)      || 0;
      paradas = parseInt(paradas) || 1;
      if (!km || !kg) return 0;
      const zona        = ccDetectarZona(destino || '', origen || '');
      const ajusteZona  = CC_ZONA_AJUSTE[zona] || 0;
      if (km < 50) {
        return Math.max(300000, 260000 + kg * 28 + 63186 * (paradas - 1));
      }
      return Math.max(CC_PRECIO_MINIMO, 3097.69*km + 217.94*kg + 0.1215*km*kg - 1.0566*km*km - 0.0034*kg*kg + 63186*paradas + ajusteZona - 306248);
    }

    // Detectar zona automáticamente a partir de origen y destino
    function ccDetectarZona(destinoTexto, origenTexto) {
      const origNorm = ccNorm(origenTexto);
      const destNorm = ccNorm(destinoTexto);
      // Si origen y todos los destinos son hubs → Hub
      const esOrigenHub = CC_HUB.some(h => origNorm.includes(h));
      const destinos = destNorm.split(',').map(d => d.trim()).filter(Boolean);
      const todoDestinoHub = destinos.length > 0 && destinos.every(d => CC_HUB.some(h => d.includes(h)));
      if (esOrigenHub && todoDestinoHub) return 'HUB';
      // Buscar por ciudad en destino
      for (const [zona, ciudades] of Object.entries(CC_ZONAS_CIUDADES)) {
        if (ciudades.some(c => destNorm.includes(c))) return zona;
      }
      return '';
    }

    // ── MINI-CALC HERO ────────────────────────────────────────────
    function hcCalc() {
      const km = parseInt(document.getElementById('hc-km').value);
      const kg = parseInt(document.getElementById('hc-kg').value);
      document.getElementById('hc-km-out').textContent = km.toLocaleString('es-CO') + ' km';
      document.getElementById('hc-kg-out').textContent = kg.toLocaleString('es-CO') + ' kg';
      const base = estimarPrecio(km, kg, 1, '', '');
      document.getElementById('hc-price').textContent = ccFmt(base);
      const r = ccRango(km);
      const ahorroPct = Math.round(Math.max(0, (1 - base / r.p75) * 100));
      const wrap = document.getElementById('hc-savings-wrap');
      if (ahorroPct > 0) {
        document.getElementById('hc-savings-pct').textContent = ahorroPct + '%';
        wrap.style.display = 'flex';
      } else {
        wrap.style.display = 'none';
      }
      // Actualizar CTA con precio
      document.getElementById('hc-cta').textContent = `Publicar mi carga · ${ccFmt(base)} →`;
    }
    hcCalc();

    // ── HERO CARD ROTATIVO — usa datos de viajesData (cargados por cargarViajes) ──
    let _heroDrawFn = function(viajes) {
      const viajesHero = [];
      for (const v of (viajes || [])) {
        const origen = (v.origen || '').split(',')[0].trim();
        const destinos = (v.destino || '').split(',').map(d => d.trim()).filter(Boolean);
        const extras = destinos.length - 1;
        const routeLabel = extras > 0 ? `${origen} → ${destinos[0]} +${extras}` : `${origen} → ${destinos[0] || '—'}`;
        const precioBase = estimarPrecio(v.km, v.peso_kg, destinos.length || 1, v.destino, v.origen);
        const precio = precioBase > 0 ? formatCOP(precioBase) : '';
        const pesoKg = parseFloat((v.peso_kg || '0').toString().replace(/[^\d.]/g,'')) || 0;
        const pesoLabel = pesoKg > 0 ? `📦 ${Number(pesoKg).toLocaleString('es-CO')} kg disponibles` : '📦 espacio disponible';
        viajesHero.push({ route: routeLabel, price: precio, space: pesoLabel });
      }
      if (viajesHero.length > 0) {
        let idx = 0;
        const routeEl = document.getElementById('hero-card-route');
        const priceEl = document.getElementById('hero-card-price');
        const spaceEl = document.getElementById('hero-card-space');
        function actualizarHeroCard() {
          if (routeEl) routeEl.textContent = viajesHero[idx].route;
          if (priceEl) priceEl.textContent = viajesHero[idx].price ? viajesHero[idx].price + ' precio ref.' : '';
          if (spaceEl) spaceEl.textContent = viajesHero[idx].space || '📦 espacio disponible';
        }
        actualizarHeroCard();
        setInterval(() => { idx = (idx+1) % viajesHero.length; actualizarHeroCard(); }, 3000);
      }
    };

    function toggleFab() {
      const menu = document.getElementById('fab-menu');
      const btn  = document.getElementById('fab-main');
      const open = menu.classList.toggle('open');
      btn.classList.toggle('open', open);
    }
    // Cerrar al hacer clic fuera
    document.addEventListener('click', function(e) {
      if (!e.target.closest('.fab-stack')) {
        document.getElementById('fab-menu').classList.remove('open');
        document.getElementById('fab-main').classList.remove('open');
      }
    });
