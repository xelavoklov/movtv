import { useEffect, useState } from 'react';
import { View, SplitLayout, SplitCol } from '@vkontakte/vkui';
import { useActiveVkuiLocation } from '@vkontakte/vk-mini-apps-router';

import { Home, Post } from './panels';
import { DEFAULT_VIEW_PANELS } from './routes';
import { fetchChannelPosts } from './utils/channel';

export const App = () => {
  const { panel: activePanel = DEFAULT_VIEW_PANELS.HOME } = useActiveVkuiLocation();
  const [posts, setPosts] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let isMounted = true;

    async function loadPosts() {
      try {
        const nextPosts = await fetchChannelPosts();
        if (!isMounted) {
          return;
        }
        setPosts(nextPosts);
      } catch (loadError) {
        if (!isMounted) {
          return;
        }
        setError(loadError instanceof Error ? loadError.message : 'Не удалось загрузить канал');
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    loadPosts();

    return () => {
      isMounted = false;
    };
  }, []);

  return (
    <SplitLayout>
      <SplitCol>
        <View activePanel={activePanel}>
          <Home id="home" posts={posts} isLoading={isLoading} error={error} />
          <Post id="post" posts={posts} isLoading={isLoading} error={error} />
        </View>
      </SplitCol>
    </SplitLayout>
  );
};
