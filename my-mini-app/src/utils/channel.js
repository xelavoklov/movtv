const CHANNEL_URL = '/channel.json';
const MEDIA_BASE_URL = 'https://xelavoklov.github.io/movtv/media';

const IMAGE_EXTENSIONS = /\.(jpg|jpeg|png|gif|webp)$/i;
const VIDEO_EXTENSIONS = /\.(mp4|webm|mov|m4v|ogg)$/i;
const AUDIO_EXTENSIONS = /\.(mp3|wav|ogg|m4a|oga)$/i;
const PDF_EXTENSION = /\.pdf$/i;

function buildPublicMediaUrl(path) {
  return encodeURI(`${MEDIA_BASE_URL}/${path}`);
}

function isPlaceholder(value) {
  return typeof value === 'string' && value.trim().startsWith('(File not included');
}

function ensureArray(value) {
  if (!value) {
    return [];
  }

  return Array.isArray(value) ? value : [value];
}

function inferMediaPath(fileName) {
  if (!fileName) {
    return '';
  }

  if (fileName.includes('/')) {
    return fileName;
  }

  if (IMAGE_EXTENSIONS.test(fileName)) {
    return `photos/${fileName}`;
  }

  if (VIDEO_EXTENSIONS.test(fileName)) {
    return `videos/${fileName}`;
  }

  if (AUDIO_EXTENSIONS.test(fileName)) {
    return `audio/${fileName}`;
  }

  return `files/${fileName}`;
}

function resolveMediaKind(fileName) {
  if (IMAGE_EXTENSIONS.test(fileName)) {
    return 'image';
  }

  if (VIDEO_EXTENSIONS.test(fileName)) {
    return 'video';
  }

  if (AUDIO_EXTENSIONS.test(fileName)) {
    return 'audio';
  }

  if (PDF_EXTENSION.test(fileName)) {
    return 'pdf';
  }

  return 'file';
}

export async function fetchChannelPosts() {
  const response = await fetch(CHANNEL_URL);

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }

  const data = await response.json();

  if (Array.isArray(data)) {
    return data;
  }

  if (data && Array.isArray(data.messages)) {
    return data.messages;
  }

  throw new Error('Файл channel.json не содержит массива messages');
}

export function getPostText(post) {
  const source = post?.text;

  if (Array.isArray(source)) {
    return source
      .map((item) => {
        if (typeof item === 'string') {
          return item;
        }

        if (item && typeof item.text === 'string') {
          return item.text;
        }

        return '';
      })
      .join('')
      .trim();
  }

  if (typeof source === 'string') {
    return source.trim();
  }

  return '';
}

export function getPreviewText(post, maxLength = 180) {
  const text = getPostText(post);

  if (text.length <= maxLength) {
    return text;
  }

  return `${text.slice(0, maxLength).trim()}...`;
}

export function getPostSenderLabel(post) {
  return post?.from || post?.person_name || post?.sender || 'Неизвестный источник';
}

export function formatPostDate(value) {
  if (!value) {
    return 'Дата не указана';
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return String(value);
  }

  return new Intl.DateTimeFormat('ru-RU', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
}

export function getPostForwardInfo(post) {
  const name = post?.forwarded_from || post?.forward?.person_name || post?.forward?.from;

  if (!name) {
    return null;
  }

  return {
    name,
    dateLabel: post?.forward_date ? formatPostDate(post.forward_date) : '',
  };
}

export function buildPersonAvatarUrl(personId) {
  if (!personId) {
    return '';
  }

  return buildPublicMediaUrl(`person/${personId}.jpg`);
}

export function getPostAvatarUrl(post) {
  return buildPersonAvatarUrl(
    post?.forwarded_from_id || post?.person_id || post?.sender_id || post?.from_id,
  );
}

export function getPostMedia(post) {
  const rawMedia = [
    ...ensureArray(post?.file_name),
    ...ensureArray(post?.photo),
    ...ensureArray(post?.real_media_path),
    ...ensureArray(post?.media),
  ]
    .map((value) => (typeof value === 'string' ? value.trim() : ''))
    .filter(Boolean)
    .filter((value) => !isPlaceholder(value));

  return [...new Set(rawMedia)].map((fileName) => {
    const path = inferMediaPath(fileName);
    const kind = resolveMediaKind(fileName);

    return {
      name: fileName.split('/').pop() || fileName,
      path,
      kind,
      label:
        kind === 'image'
          ? 'Изображение'
          : kind === 'video'
            ? 'Видео'
            : kind === 'audio'
              ? 'Аудио'
              : kind === 'pdf'
                ? 'PDF'
                : 'Файл',
      url: buildPublicMediaUrl(path),
    };
  });
}