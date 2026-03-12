import { useDeferredValue, useMemo, useState } from 'react';
import {
  Avatar,
  Banner,
  Button,
  Card,
  CardGrid,
  Div,
  FormItem,
  Group,
  Header,
  Input,
  Panel,
  PanelHeader,
  Placeholder,
  RichCell,
  Separator,
  SimpleCell,
} from '@vkontakte/vkui';
import { useRouteNavigator } from '@vkontakte/vk-mini-apps-router';
import PropTypes from 'prop-types';

import {
  formatPostDate,
  getPostForwardInfo,
  getPostAvatarUrl,
  getPostMedia,
  getPostSenderLabel,
  getPostText,
  getPreviewText,
} from '../utils/channel';

import './feed.css';

export const Home = ({ id, posts, isLoading, error }) => {
  const routeNavigator = useRouteNavigator();
  const [query, setQuery] = useState('');
  const deferredQuery = useDeferredValue(query);

  const filteredPosts = useMemo(() => {
    const normalizedQuery = deferredQuery.trim().toLowerCase();

    if (!normalizedQuery) {
      return posts;
    }

    return posts.filter((post) => {
      const haystack = [
        String(post.id ?? ''),
        getPostSenderLabel(post),
        getPostText(post),
        post.forwarded_from,
        post.forwarded_from_name,
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();

      return haystack.includes(normalizedQuery);
    });
  }, [deferredQuery, posts]);

  const featuredPost = filteredPosts[0];

  const openPost = (postId) => {
    routeNavigator.push(`/post/${postId}`);
  };

  return (
    <Panel id={id}>
      <PanelHeader>movtv</PanelHeader>

      <Group>
        <Div className="feed-hero">
          <div className="feed-hero__eyebrow">VK Mini App MVP</div>
          <div className="feed-hero__title">Архив канала в формате мобильной ленты</div>
          <div className="feed-hero__text">
            Локально загружается channel.json, посты фильтруются по тексту и id, а полный пост
            открывается отдельным экраном.
          </div>
        </Div>
      </Group>

      <Group>
        <Banner
          mode="image"
          header={`Постов: ${posts.length}`}
          subheader={
            error
              ? 'Загрузка завершилась с ошибкой'
              : isLoading
                ? 'Читаю архив канала'
                : `После фильтрации: ${filteredPosts.length}`
          }
          actions={
            featuredPost ? (
              <Button size="m" mode="primary" onClick={() => openPost(featuredPost.id)}>
                Открыть первый пост
              </Button>
            ) : null
          }
        />
      </Group>

      <Group header={<Header size="s">Поиск</Header>}>
        <FormItem top="Фильтр по id, автору и тексту">
          <Input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Например: 25, xelavoklovlive, переписка"
          />
        </FormItem>
      </Group>

      {isLoading ? (
        <Group>
          <Placeholder>Загружаю посты из channel.json</Placeholder>
        </Group>
      ) : null}

      {error ? (
        <Group>
          <Placeholder>
            Не удалось загрузить архив: {error}
          </Placeholder>
        </Group>
      ) : null}

      {!isLoading && !error && filteredPosts.length === 0 ? (
        <Group>
          <Placeholder>По этому запросу ничего не найдено.</Placeholder>
        </Group>
      ) : null}

      {!isLoading && !error && filteredPosts.length > 0 ? (
        <Group header={<Header size="s">Лента</Header>}>
          <CardGrid size="l">
            {filteredPosts.map((post) => {
              const senderLabel = getPostSenderLabel(post);
              const text = getPreviewText(post, 240);
              const media = getPostMedia(post);
              const forwardInfo = getPostForwardInfo(post);
              const cover = media[0];
              const avatarUrl = getPostAvatarUrl(post);

              return (
                <Card key={post.id} mode="shadow" className="feed-card">
                  <button type="button" className="feed-card__button" onClick={() => openPost(post.id)}>
                    {cover && cover.kind === 'image' ? (
                      <img
                        className="feed-card__cover"
                        src={cover.url}
                        alt={cover.name}
                        loading="lazy"
                      />
                    ) : null}

                    {cover && cover.kind === 'video' ? (
                      <div className="feed-card__cover-shell">
                        <video
                          className="feed-card__cover"
                          src={cover.url}
                          preload="metadata"
                          muted
                          playsInline
                        />
                        <div className="feed-card__badge feed-card__badge--overlay">Видео</div>
                      </div>
                    ) : null}

                    <Div>
                      <RichCell
                        disabled
                        before={
                          avatarUrl ? (
                            <Avatar size={40} src={avatarUrl} />
                          ) : (
                            <Avatar size={40}>{senderLabel[0]}</Avatar>
                          )
                        }
                        caption={`ID ${post.id}`}
                        subhead={formatPostDate(post.date)}
                        after={media.length ? `${media.length} медиа` : null}
                      >
                        {senderLabel}
                      </RichCell>

                      {forwardInfo ? (
                        <SimpleCell disabled subtitle={forwardInfo.dateLabel || 'Пересланное сообщение'}>
                          Переслано от {forwardInfo.name}
                        </SimpleCell>
                      ) : null}

                      <div className="feed-card__text">{text || 'Без текста'}</div>

                      {cover && cover.kind !== 'image' && cover.kind !== 'video' ? (
                        <div className="feed-card__badge">{cover.label}</div>
                      ) : null}
                    </Div>
                  </button>
                </Card>
              );
            })}
          </CardGrid>
          <Separator />
          <Div className="feed-footer">Следующий этап: вынести данные на API или подключить пагинацию.</Div>
        </Group>
      ) : null}
    </Panel>
  );
};

Home.propTypes = {
  id: PropTypes.string.isRequired,
  posts: PropTypes.arrayOf(PropTypes.object).isRequired,
  isLoading: PropTypes.bool.isRequired,
  error: PropTypes.string.isRequired,
};
