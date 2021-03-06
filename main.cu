#include <iostream>
#include <sstream>
#include <thread>
#include <vector>
#include <cmath>

#include <SFML/Graphics.hpp>

__global__ void mandelize(double const x_offset, double const y_offset,
                         double const x_scale, double const y_scale,
                         int const max_iter, int const max_color,
                         double *mus)
{
    int idx = blockIdx.x*gridDim.x + threadIdx.x;
    int x = threadIdx.x;
    int y = blockIdx.x;
    double r, i, r_0, i_0;
    r_0 = x_offset + x_scale * x;
    i_0 = y_offset + y_scale * y;
    r = i = 0;
    int iter = 0;
    while (iter < max_iter)
    {
        double tr = r * r - i * i + r_0;
        i = 2 * r*i + i_0;
        r = tr;
        if (r*r + i*i > 4)
            break;
        ++iter;
    }
    if (iter == max_iter)
        iter = 0;
    double c_size = std::sqrt(r*r+i*i);
    double mu = (iter+1-log(log(c_size))/log(2)/log(2))/max_iter*max_color;
    mus[idx] = mu;
};

int main()
{
    constexpr int size = 700;

    sf::Image fractal;
    fractal.create(size, size);
    sf::Texture texture;
    sf::Sprite sprite;
    sf::RenderWindow window(sf::VideoMode(size, size), "mandelbrot");
    sf::Font font; font.loadFromFile("arial.ttf");
    sf::Text text;
    text.setFont(font);
    text.setCharacterSize(20);
    text.setFillColor(sf::Color::White);

    std::vector<sf::Color> colors{
            {0,7,100},
            {32,107,203},
            {237,255,255},
            {255,170,0},
            {0,2,0},
        };

    auto max_color = colors.size() - 1;

    double min_re = -2.0;
    double max_re = 1.0;
    double min_im = -1.5;
    double max_im = 1.5;

    int max_iter = 256;
    double zoom = 1.;

    double *mus;
    cudaMallocManaged(&mus, sizeof(double)*size*size);

    auto compute = [&]()
    {
        auto x_scale = (max_re - min_re) / size;
        auto y_scale = (max_im - min_im) / size;
        mandelize<<<size,size>>>(min_re, min_im, x_scale, y_scale, max_iter, max_color, mus);
        cudaDeviceSynchronize();

        for (int idx{0}; idx < size*size; ++idx)
        {
            auto x = idx % size;
            auto y = idx / size;

            auto mu = mus[idx];
            auto i_mu = static_cast<size_t>(mu);
            auto v = colors[i_mu];
            auto u = colors[i_mu + 1];
            double a = mu - i_mu;
            auto h = 1 - a;
            auto c = sf::Color(h*v.r+a*u.r, h*v.g+a*u.g, h*v.b+a*u.b);
            fractal.setPixel(x, y, c);
        }
    };

    compute();

    while (window.isOpen())
    {
        sf::Event event;
        while (window.pollEvent(event))
        {
            if (event.type == sf::Event::Closed)
                window.close();
            
            if (event.type == sf::Event::KeyPressed)
                if (event.key.code == sf::Keyboard::Escape)
                    window.close();
            
            if (event.type == sf::Event::KeyPressed)
            {
                double w = (max_re - min_re)*0.2;
                double h = (max_im - min_im)*0.2;

                if (event.key.code == sf::Keyboard::Left)
                    min_re -= w, max_re -= w;
                if (event.key.code == sf::Keyboard::Right)
                    min_re += w, max_re += w;
                if (event.key.code == sf::Keyboard::Up)
                    min_im -= h, max_im -= h;
                if (event.key.code == sf::Keyboard::Down)
                    min_im += h, max_im += h;
                if (event.key.code == sf::Keyboard::S)
                {
                    std::cout << "saved\n";
                    std::ostringstream str;
                    str << zoom;
                    texture.copyToImage().saveToFile("mandel-"+str.str()+"x.png");
                    continue;
                }
                compute();
            }
            
            if (event.type == sf::Event::MouseButtonPressed)
            {
                auto zoomX = [&](double scale)
                {
                    long double x = min_re + (max_re - min_re)*event.mouseButton.x / size;
                    long double y = min_im + (max_im - min_im)*event.mouseButton.y / size;
                    long double tmp_x = x - (max_re - min_re) / 2 / scale;
                    max_re = x + (max_re - min_re) / 2 / scale;
                    min_re = tmp_x;
                    long double tmp_y = y - (max_im - min_im) / 2 / scale;
                    max_im = y + (max_im - min_im) / 2 / scale;
                    min_im = tmp_y;
                };
                
                if (event.mouseButton.button == sf::Mouse::Left)
                {
                    zoomX(2);
                    zoom *= 2;
                }

                if (event.mouseButton.button == sf::Mouse::Right)
                {
                    zoomX(1./2);
                    zoom /= 2;
                }
                compute();
            }

            if (event.type == sf::Event::MouseWheelScrolled)
            {
                if (event.mouseWheelScroll.wheel == sf::Mouse::VerticalWheel)
                {
                    if (event.mouseWheelScroll.delta > 0)
                        max_iter *= 2;
                    else
                        max_iter /= 2;
                    if (max_iter < 1)
                        max_iter = 1;
                }

                compute();
            }
        }

        window.clear();
        texture.loadFromImage(fractal);
        sprite.setTexture(texture);
        window.draw(sprite);
        std::ostringstream str;
        str << "max iter:" << max_iter << "\nzoom:" << zoom;
        text.setString(str.str());
        window.draw(text);
        window.display();
    }

    cudaFree(mus);
}