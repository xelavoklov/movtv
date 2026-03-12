import {
  Avatar,
  Button,
  Div,
  Group,
  Header,
  Panel,
  PanelHeader,
  PanelHeaderBack,
  Placeholder,
  RichCell,
  SimpleCell,
} from '@vkontakte/vkui';
import { useParams, useRouteNavigator } from '@vkontakte/vk-mini-apps-router';
import PropTypes from 'prop-types';

import {
  formatPostDate,
  getPostForwardInfo,
  getPostAvatarUrl,
  getPostMedia,
  getPostSenderLabel,
  getPostText,
} from '../utils/channel';

import './feed.css';

const renderMedia = (mediaItem) => {
  if (mediaItem.kind === 'image') {
    return <img key={mediaItem.url} className="post-media__image" src={mediaItem.url} alt={mediaItem.name} loading="lazy" />;
  }

  if (mediaItem.kind === 'video') {
    return <video key={mediaItem.url} className="post-media__video" src={mediaItem.url} controls preload="metadata" />;
  }

  if (mediaItem.kind === 'audio') {
    return (
      <div key={mediaItem.url} className="post-media__file">
        <div className="post-media__label">{mediaItem.label}</div>
        <audio src={mediaItem.url} controls preload="metadata" />
      </div>
    );
  }

  return (
    <a key={mediaItem.url} className="post-media__file post-media__link" href={mediaItem.url} target="_blank" rel="noreferrer">
      {mediaItem.label}: {mediaItem.name}
    </a>
  );
};

export const Post = ({ id, posts, isLoading, error }) => {
  const routeNavigator = useRouteNavigator();
  const params = useParams();
  const postId = params?.postId;
  const post = posts.find((item) => String(item.id) === String(postId));

  if (isLoading) {
    return (
      <Panel id={id}>
        <PanelHeader before={<PanelHeaderBack onClick={() => routeNavigator.back()} />}>Пост</PanelHeader>
        <Placeholder>Загружаю пост</Placeholder>
      </Panel>
    );
  }

  if (error) {
    return (
      <Panel id={id}>
        <PanelHeader before={<PanelHeaderBack onClick={() => routeNavigator.back()} />}>Пост</PanelHeader>
        <Placeholder>Ошибка загрузки: {error}</Placeholder>
      </Panel>
    );
  }

  if (!post) {
    return (
      <Panel id={id}>
        <PanelHeader before={<PanelHeaderBack onClick={() => routeNavigator.back()} />}>Пост</PanelHeader>
        <Placeholder action={<Button onClick={() => routeNavigator.replace('/')}>Вернуться к ленте</Button>}>
          Пост не найден.
        </Placeholder>
      </Panel>
    );
  }

  const senderLabel = getPostSenderLabel(post);
  const text = getPostText(post);
  const media = getPostMedia(post);
  const forwardInfo = getPostForwardInfo(post);
  const avatarUrl = getPostAvatarUrl(post);

  return (
    <Panel id={id}>
      <PanelHeader before={<PanelHeaderBack onClick={() => routeNavigator.back()} />}>Пост #{post.id}</PanelHeader>

      <Group>
        <Div className="post-hero">
          <div className="post-hero__eyebrow">Детальный просмотр</div>
          <div className="post-hero__title">{senderLabel}</div>
          <div className="post-hero__text">{formatPostDate(post.date)}</div>
        </Div>
      </Group>

      <Group header={<Header size="s">Автор</Header>}>
        <RichCell
          disabled
          before={avatarUrl ? <Avatar size={48} src={avatarUrl} /> : <Avatar size={48}>{senderLabel[0]}</Avatar>}
          caption={`ID поста ${post.id}`}
          subhead={post.from_id || post.sender_id || 'Источник не указан'}
        >
          {senderLabel}
        </RichCell>
        {forwardInfo ? (
          <SimpleCell disabled subtitle={forwardInfo.dateLabel || 'Переслано'}>
            Переслано от {forwardInfo.name}
          </SimpleCell>
        ) : null}
      </Group>

      <Group header={<Header size="s">Текст</Header>}>
        <Div className="post-text">{text || 'У поста нет текстового содержимого.'}</Div>
      </Group>

      {media.length ? (
        <Group header={<Header size="s">Медиа</Header>}>
          <Div className="post-media">{media.map(renderMedia)}</Div>
        </Group>
      ) : null}
    </Panel>
  );
};

Post.propTypes = {
  id: PropTypes.string.isRequired,
  posts: PropTypes.arrayOf(PropTypes.object).isRequired,
  isLoading: PropTypes.bool.isRequired,
  error: PropTypes.string.isRequired,
};